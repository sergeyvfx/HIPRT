
newoption {
    trigger = "bakeKernel",
    description = "Encrypt and bake kernels"
}

newoption {
    trigger = "bitcode",
    description = "Enable bitcode linking"
}

newoption {
    trigger = "precompile",
    description = "Precompile kernels"
}

newoption {
    trigger = "hiprtew",
    description = "Use hiprtew"
}

newoption {
    trigger = "noUnittest",
    description = "Don't build unit tests",
}

newoption {
    trigger = "noEncrypt",
    description = "Don't encrypt kernel source and binaries",
}

function copydir(src_dir, dst_dir, filter, single_dst_dir)
    filter = filter or "**"
    src_dir = src_dir .. "/"
    print('copy "' .. src_dir .. filter .. '" to "' .. dst_dir .. '".')
    dst_dir = dst_dir .. "/"
    local dir = path.rebase(".", path.getabsolute("."), src_dir) -- root dir, relative from src_dir

    os.chdir(src_dir) -- change current directory to src_dir
    local matches = os.matchfiles(filter)
    os.chdir(dir) -- change current directory back to root

    local counter = 0
    for k, v in ipairs(matches) do
        local target = iif(single_dst_dir, path.getname(v), v)
        --make sure, that directory exists or os.copyfile() fails
        os.mkdir(path.getdirectory(dst_dir .. target))
        if os.copyfile(src_dir .. v, dst_dir .. target) then
            counter = counter + 1
        end
    end

    if counter == #matches then
        print(counter .. " files copied.")
        return true
    else
        print("Error: " .. counter .. "/" .. #matches .. " files copied.")
        return nil
    end
end

function file_exists(file)
    local f = io.open(file, "rb")
    if f then f:close() end
    return f ~= nil
  end
  
function lines_from(file)
    if not file_exists(file) then return {} end
    local lines = {}
    for line in io.lines(file) do 
      lines[#lines + 1] = line
    end
    return lines
end

function read_file(file)
    local lines = lines_from(file)
    str = ''
    for num, line in pairs(lines) do
        str = str..line.."\n"
    end
    return str
end

function get_version(file)
    local lines = lines_from(file)
    major = tonumber(lines[1])
    minor = tonumber(lines[2])
    patch = "0x"..(lines[3])
    return major, minor, patch
end


-- find the path of 'Hipcc' from PATH
-- return nil if not exist
-- only works for linux ( for now )
function findHipccPath()

	if os.host() ~= "linux" then
		return nil
	end

	local cmd = 'which hipcc 2>/dev/null'

	local f = io.popen(cmd)
	local hipccPath = f:read("*a")
	f:close()

	if hipccPath == nil or hipccPath == '' then
		print("hipccPath nil");
		return nil
	else
		print("-- hipccPath = " .. hipccPath );
		-- Remove any trailing whitespace
		hipccPath = hipccPath:gsub("%s+$", "")

		-- Extract the directory from the full path
		local dir = hipccPath:match("(.+)/[^/]+$")
		return dir
	end
end



function get_hip_sdk_verion()
	
	if os.ishost("windows") then
		root = '.\\'
	end
	
	hipCommand = 'hipcc'
	HIP_PATH = os.getenv("HIP_PATH")
	PATH = os.getenv("PATH")
	
	
	
	hipccFromPATH = findHipccPath()
	if fromPATH ~= nil then
		print( "hipcc found from PATH: ".. hipccFromPATH )
	end
	
	
	
	if os.ishost("windows") then


			if not HIP_PATH then
				-- if the HIP_PATH env var is not set, we assume there is a 'hipSdk' folder at the root of the project.
				HIP_PATH = path.getabsolute(root .. 'hipSdk') -- convert the path to absolute
			end
		
            if string.sub(HIP_PATH, -1, -1) == '\\' or string.sub(HIP_PATH, -1, -1) == '/' then
                HIP_PATH = string.sub(HIP_PATH, 1, -2)
            end
			
			-- HIP_PATH is expected to look like:   C:\Program Files\AMD\ROCm\5.7
			print("using HIP_PATH = " .. HIP_PATH)
			
			if os.isfile(HIP_PATH .. '\\bin\\hipcc.exe') then
				-- in newer version of HIP SDK (>= 6.3), we are using 'hipcc.exe --version' to check the version
				-- print("using hipcc.exe to get the version.")
				hipCommand = '\"' .. HIP_PATH..'\\bin\\hipcc.exe\"'
			elseif os.isfile(HIP_PATH .. '\\bin\\hipcc') then
				-- in older version of HIP SDK, we are using 'perl hipcc --version' to check the version
				-- print("using perl hipcc to get the version.")
				hipCommand = '\"' .. HIP_PATH..'\\bin\\hipcc\"'
			else
				print("ERROR: hipcc.exe or hipcc not found in the SDK path.")
				hipCommand = 'hipcc'
			end
	
	-- for LINUX
	else
	
		if not HIP_PATH then
			if hipccFromPATH ~= nil then
				hipCommand = 'hipcc'
			end
			
		-- if HIP_PATH is set, we take the path from it.
		else
			if string.sub(HIP_PATH, -1, -1) == '\\' or string.sub(HIP_PATH, -1, -1) == '/' then
				HIP_PATH = string.sub(HIP_PATH, 1, -2)
			end
			
			hipCommand = '\"' .. HIP_PATH..'/bin/hipcc\"'
		end
		
	end
	
	
	tmpFile = os.tmpname ()
	fullcommand = hipCommand .. " --version > " .. tmpFile
	print("Executing: " .. fullcommand);
	os.execute (fullcommand)
	
	local version
	for line in io.lines (tmpFile) do
		print (line)
		version =  string.sub(line, string.find(line, "%d.%d"))
		break
	end
	os.remove (tmpFile)

    if version == nil or version == '' then
        version = "HIP_SDK_NOT_FOUND"
    end

	return version, HIP_PATH
end



hipSdkVersion, hipFinalPath = get_hip_sdk_verion()
print( "HIP_VERSION_STR: "..hipSdkVersion )
if hipFinalPath ~= nil then
	print( "HIP SDK path: " .. hipFinalPath )
else
	print( "no HIP SDK folder found." )
end

function write_version_info(in_file, header_file, version_file)
	if not file_exists(version_file) then
		print("Version.txt file missing!\n")
		return
	end
	if not file_exists(in_file) then 
		print(string.format("%s file is missing!\n", in_file))
		return
	end
	
	HIPRT_MAJOR_VERSION, HIPRT_MINOR_VERSION, HIPRT_PATCH_VERSION = get_version(version_file)
	HIPRT_VERSION = HIPRT_MAJOR_VERSION * 1000 + HIPRT_MINOR_VERSION 
	HIPRT_API_VERSION = HIPRT_VERSION 
	HIPRT_VERSION_STR = string.format("%05d", HIPRT_VERSION)
	print( "HIPRT_API_VERSION: "..HIPRT_VERSION_STR .."_".. HIPRT_PATCH_VERSION )
	header = read_file(in_file)
	header = header:gsub("@HIPRT_MAJOR_VERSION@", HIPRT_MAJOR_VERSION)
	header = header:gsub("@HIPRT_MINOR_VERSION@", HIPRT_MINOR_VERSION)
	header = header:gsub("@HIPRT_PATCH_VERSION@", HIPRT_PATCH_VERSION)
	header = header:gsub("@HIPRT_API_VERSION@", HIPRT_API_VERSION)
	header = header:gsub("@HIPRT_VERSION_STR@", "\""..HIPRT_VERSION_STR.."\"")
	header = header:gsub("@HIP_VERSION_STR@", "\""..hipSdkVersion.."\"")
	file = io.open(header_file, "w")
	file:write(header)
	file:close()
end
workspace "hiprt"
    configurations {"Debug", "Release", "RelWithDebInfo", "DebugGpu" }
    language "C++"
    platforms "x64"
    architecture "x86_64"

	if os.ishost("windows") then
		defines {"__WINDOWS__"}
	end
    characterset("MBCS")

    filter {"platforms:x64", "configurations:Debug or configurations:DebugGpu"}
      targetsuffix "64D"
      defines {"DEBUG"}
      symbols "On"
    filter {"platforms:x64", "configurations:DebugGpu"}
      defines {"DEBUG_GPU"}
    filter {"platforms:x64", "configurations:Release or configurations:RelWithDebInfo"}
      targetsuffix "64"
      defines {"NDEBUG"}
      optimize "On"
    filter {"platforms:x64", "configurations:RelWithDebInfo"}
      symbols "On"
    filter {}
	flags { "MultiProcessorCompile" }

    if os.ishost("windows") then
        buildoptions {"/wd4244", "/wd4305", "/wd4018", "/wd4996", "/Zc:__cplusplus"}
    end
    if os.ishost("linux") then
        buildoptions {"-fvisibility=hidden"}
    end
    defines {"__USE_HIP__"}

    -- this define is to identify that we are on the public repository of HIPRT.
    -- it helps AMD to maintain both a public and a private repo for experimentation.
    defines {"HIPRT_PUBLIC_REPO"}
    
    

    -- enable CUDA if possible
    include "./contrib/Orochi/Orochi/enable_cuew"


    targetdir "dist/bin/%{cfg.buildcfg}"    
    location "build/"
    
    write_version_info("./hiprt/hiprt.h.in", "./hiprt/hiprt.h", "version.txt")
	write_version_info("./hiprt/hiprtew.h.in", "./hiprt/hiprtew.h", "version.txt")

    HIPRT_NAME = "hiprt"..HIPRT_VERSION_STR
    project( HIPRT_NAME )
        cppdialect "C++17"
        kind "SharedLib"
        defines {"HIPRT_EXPORTS"}
	if _OPTIONS["bitcode"] then
		defines {"HIPRT_BITCODE_LINKING"}
        defines {"ORO_PRECOMPILED"}
	end

    if not _OPTIONS["no-encrypt"] then
        defines {"HIPRT_ENCRYPT"}
    end

    if _OPTIONS["precompile"] then
		cmdExec = "cd ./scripts/bitcodes/ && python compile.py"
		if hipFinalPath ~= nil then
			cmdExec = cmdExec .. " --hipSdkPath \"" .. hipFinalPath .. "\""
		end
		print("Executing: " .. cmdExec);
        os.execute( cmdExec )
    end

    if _OPTIONS["bakeKernel"] or _OPTIONS["bitcode"] then
        print(">> BakeKernel Executed")
        if os.ishost("windows") then
            os.execute("mkdir hiprt\\cache")
            os.execute("tools\\bakeKernel.bat")
        else
            os.execute("mkdir hiprt/cache")
            os.execute("./tools/bakeKernel.sh")
        end
        if _OPTIONS["bakeKernel"] then
            defines {"HIPRT_LOAD_FROM_STRING"}
            defines { "ORO_PP_LOAD_FROM_STRING" }
        end
        defines {"HIPRT_BAKE_KERNEL_GENERATED"}
    end
    if os.istarget("windows") then
        links{ "version" }
    end

    externalincludedirs {"./"}
    files {"hiprt/**.h", "hiprt/**.cpp", "hiprt/**.inl"}
    removefiles {"hiprt/bitcodes/**"}
    externalincludedirs { "./contrib/Orochi/" }
    files {"contrib/Orochi/Orochi/**.h", "contrib/Orochi/Orochi/**.cpp"}
    files {"contrib/Orochi/contrib/cuew/**.h", "contrib/Orochi/contrib/cuew/**.cpp"}
    files {"contrib/Orochi/contrib/hipew/**.h", "contrib/Orochi/contrib/hipew/**.cpp"}
    files {"contrib/Orochi/ParallelPrimitives/**.h", "contrib/Orochi/ParallelPrimitives/**.cpp"}

	
	if not _OPTIONS["noUnittest"] then
		project( "unittest" )
			cppdialect "C++17"
			kind "ConsoleApp"
			if _OPTIONS["bitcode"] then
				defines {"HIPRT_BITCODE_LINKING"}
			end
			if os.ishost("windows") then
				buildoptions { "/wd4244" }
				links{ "version" }
			end
			externalincludedirs {"./"}
			links { HIPRT_NAME }
			
			if os.ishost("linux") then
				links { "pthread", "dl" }
			end
			files { "test/hiprtT*.h", "test/hiprtT*.cpp", "test/shared.h", "test/main.cpp", "test/CornellBox.h", "test/kernels/*.h" }
			externalincludedirs { "./contrib/Orochi/" }
			files {"contrib/Orochi/Orochi/**.h", "contrib/Orochi/Orochi/**.cpp"}
			files {"contrib/Orochi/contrib/cuew/**.h", "contrib/Orochi/contrib/cuew/**.cpp"}
			files {"contrib/Orochi/contrib/hipew/**.h", "contrib/Orochi/contrib/hipew/**.cpp"}

			files { "contrib/gtest-1.6.0/gtest-all.cc" }
			externalincludedirs { "contrib/gtest-1.6.0/" }
			defines { "GTEST_HAS_TR1_TUPLE=0" }
			externalincludedirs { "contrib/embree/include/" }
			if os.istarget("windows") then
				libdirs{"contrib/embree/win/"}
				copydir( "./contrib/embree/win", "./dist/bin/Release/", "*.dll" )
				copydir( "./contrib/embree/win", "./dist/bin/Debug/", "*.dll" )
				libdirs{"contrib/bin/win64"}
				copydir( "./contrib/Orochi/contrib/bin/win64", "./dist/bin/Release/", "*.dll" )
				copydir( "./contrib/Orochi/contrib/bin/win64", "./dist/bin/Debug/", "*.dll" )
			end
			if os.istarget("linux") then
				libdirs{"contrib/embree/linux/"}
			end
			links{ "embree4", "tbb" }

	end

	if _OPTIONS["hiprtew"] then
		 project( "hiprtewtest" )
				 kind "ConsoleApp"
				 defines {"HIPRT_EXPORTS"}
				 defines {"USE_HIPRTEW"}
				 if os.ishost("windows") then
						 buildoptions { "/wd4244" }
						 links{ "version" }
				 end
				 externalincludedirs {"./", "./contrib/Orochi/"}
				 if os.ishost("linux") then
						 links { "pthread", "dl"}
				 end
				 files {"contrib/Orochi/Orochi/**.h", "contrib/Orochi/Orochi/**.cpp"}
				 files {"contrib/Orochi/contrib/**.h", "contrib/Orochi/contrib/**.cpp"}
				 files { "test/hiprtewTest.h", "test/hiprtewTest.cpp" }

				 files { "contrib/gtest-1.6.0/gtest-all.cc" }
				 externalincludedirs { "contrib/gtest-1.6.0/" }
				 defines { "GTEST_HAS_TR1_TUPLE=0" }
    end
