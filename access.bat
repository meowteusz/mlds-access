@echo off
setlocal enabledelayedexpansion

:: MLDS SSH Access Setup Script for Windows
:: This script automates SSH key setup for MLDS server access
:: It generates SSH keys, copies them to the NFS server, and updates SSH config
:: Created specifically for Northwestern University NetID authentication

echo [INFO] Starting MLDS SSH Access Setup Script

:: Step 1: Check for required tools
echo [INFO] Checking required tools
where ssh >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] SSH tools not found. Please install OpenSSH for Windows.
    echo [INFO] You can install OpenSSH client from Windows Settings ^> Apps ^> Optional features
    exit /b 1
)

where ssh-keygen >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] SSH-keygen not found. Please install OpenSSH for Windows.
    echo [INFO] You can install OpenSSH client from Windows Settings ^> Apps ^> Optional features
    exit /b 1
)

echo [SUCCESS] Required tools found

:: Step 2: NetID Query
set "NETID="
if exist "%USERPROFILE%\.ssh\config" (
    set /p NETID="Please enter your Northwestern NetID: "
    echo [INFO] NetID set to: %NETID%
) else (
    echo [WARNING] No SSH config found at %USERPROFILE%\.ssh\config
    echo [INFO] An SSH config file helps you organize and simplify SSH connections.
    echo [INFO] After this setup, we'll create one for you, but you might want to learn more about them.
    echo [INFO] Tutorial: https://linuxize.com/post/using-the-ssh-config-file/
    set /p NETID="Please enter your Northwestern NetID: "
    echo [INFO] NetID set to: %NETID%
)

:: Validate NetID format (basic check)
echo %NETID%| findstr /R "^[a-z0-9]*$" >nul
if %ERRORLEVEL% neq 0 (
    echo [WARNING] NetID format looks unusual. Northwestern NetIDs typically contain only lowercase letters and numbers.
    set /p CONFIRM="Continue with this NetID? (y/n): "
    if /i not "!CONFIRM!"=="y" (
        echo [ERROR] Exiting at user request
        exit /b 1
    )
)

:: Step 3: Generate SSH keys
set "KEY_NAME=mlds-access-%NETID%"
set "KEY_PATH=%USERPROFILE%\.ssh\%KEY_NAME%"

echo [INFO] Checking for existing SSH keys
if exist "%KEY_PATH%" (
    echo [WARNING] SSH key already exists at %KEY_PATH%
    set /p OVERWRITE="Do you want to generate a new key and overwrite it? (y/n): "
    if /i "!OVERWRITE!"=="y" (
        echo [INFO] Generating new SSH key pair
        ssh-keygen -t ed25519 -f "%KEY_PATH%" -N "" -C "MLDS access key for %NETID%"
        if %ERRORLEVEL% equ 0 (
            echo [SUCCESS] SSH key pair generated
        ) else (
            echo [ERROR] Failed to generate SSH key pair
        )
    ) else (
        echo [INFO] Using existing key
    )
) else (
    echo [INFO] Generating new SSH key pair
    :: Create .ssh directory if it doesn't exist
    if not exist "%USERPROFILE%\.ssh" mkdir "%USERPROFILE%\.ssh"
    ssh-keygen -t ed25519 -f "%KEY_PATH%" -N "" -C "MLDS access key for %NETID%"
    if %ERRORLEVEL% equ 0 (
        echo [SUCCESS] SSH key pair generated
    ) else (
        echo [ERROR] Failed to generate SSH key pair
        exit /b 1
    )
)

:: Fix permissions (Windows equivalent using icacls)
icacls "%KEY_PATH%" /inheritance:r /grant:r "%USERNAME%:(R,W)" >nul
icacls "%KEY_PATH%.pub" /inheritance:r /grant:r "%USERNAME%:(R,W)" >nul
echo [SUCCESS] Set proper permissions on key files

:: Step 4: Copy SSH key to NFS
echo [INFO] Copying SSH key to NFS storage
echo [INFO] You may be prompted for your Northwestern NetID password

:: Windows doesn't have a direct equivalent to ssh-copy-id, so we'll create our own
:: First, ensure the remote .ssh directory exists and has proper permissions
echo [INFO] Connecting to remote server (this may take some time)...
ssh -o ConnectTimeout=0 %NETID%@mlds-deepdish4.ads.northwestern.edu "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to create remote .ssh directory. Please check your NetID and password.
    exit /b 1
)

:: Now append the public key to the authorized_keys file
echo [INFO] Copying SSH key (this may take some time)...
type "%KEY_PATH%.pub" | ssh -o ConnectTimeout=0 %NETID%@mlds-deepdish4.ads.northwestern.edu "cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to copy SSH key to NFS. Please check your NetID and password.
    exit /b 1
)
echo [SUCCESS] SSH key copied to NFS

:: Step 5: Update SSH config
echo [INFO] Updating SSH config

:: Backup existing config if it exists
if exist "%USERPROFILE%\.ssh\config" (
    for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (
        set "datestamp=%%c%%a%%b"
    )
    for /f "tokens=1-2 delims=: " %%a in ('time /t') do (
        set "timestamp=%%a%%b"
    )
    copy "%USERPROFILE%\.ssh\config" "%USERPROFILE%\.ssh\config.backup.!datestamp!!timestamp!" >nul
    echo [SUCCESS] Backed up existing SSH config
)

:: Ask for server nickname
set "SERVER_NICKNAME=wolf"
set /p SERVER_NICKNAME="Enter a nickname for the server (default: wolf): "

:: Check if the entry already exists
set "UPDATE_CONFIG=y"
if exist "%USERPROFILE%\.ssh\config" (
    findstr /C:"Host %SERVER_NICKNAME%" "%USERPROFILE%\.ssh\config" >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        echo [WARNING] An entry for '%SERVER_NICKNAME%' already exists in your SSH config
        set /p UPDATE_CONFIG="Do you want to update it? (y/n): "
        if /i "!UPDATE_CONFIG!"=="y" (
            :: Create a temporary file without the existing entry
            type nul > "%TEMP%\ssh_config.tmp"
            set "SKIP_LINES=false"
            for /f "usebackq delims=" %%a in ("%USERPROFILE%\.ssh\config") do (
                set "line=%%a"
                if "!line!"=="Host %SERVER_NICKNAME%" (
                    set "SKIP_LINES=true"
                ) else if "!SKIP_LINES!"=="true" (
                    if "!line!"=="" (
                        set "SKIP_LINES=false"
                    ) else if "!line:~0,1!"==" " (
                        REM Skip indented lines that are part of the host
                    ) else if "!line:~0,4!"=="Host" (
                        set "SKIP_LINES=false"
                        echo !line! >> "%TEMP%\ssh_config.tmp"
                    )
                ) else (
                    echo !line! >> "%TEMP%\ssh_config.tmp"
                )
            )
            copy "%TEMP%\ssh_config.tmp" "%USERPROFILE%\.ssh\config" >nul
            del "%TEMP%\ssh_config.tmp"
            echo [SUCCESS] Removed existing entry for %SERVER_NICKNAME%
        ) else (
            echo [INFO] Skipping SSH config update
        )
    )
)

:: Add new entry if needed
if /i not "%UPDATE_CONFIG%"=="n" (
    :: Ensure file exists
    if not exist "%USERPROFILE%\.ssh\config" type nul > "%USERPROFILE%\.ssh\config"
    
    :: Append new config
    echo. >> "%USERPROFILE%\.ssh\config"
    echo Host %SERVER_NICKNAME% >> "%USERPROFILE%\.ssh\config"
    echo     HostName wolf.analytics.private >> "%USERPROFILE%\.ssh\config"
    echo     User %NETID% >> "%USERPROFILE%\.ssh\config"
    echo     IdentityFile %USERPROFILE%\.ssh\%KEY_NAME% >> "%USERPROFILE%\.ssh\config"
    
    echo [SUCCESS] Updated SSH config
    
    :: Fix permissions on config file (Windows equivalent)
    icacls "%USERPROFILE%\.ssh\config" /inheritance:r /grant:r "%USERNAME%:(R,W)" >nul
)

:: Step 6: Test connection
echo [INFO] Testing connection to the server
echo [INFO] Attempting to connect to test server and create a file. This will be deleted immediately.

:: Run the test command
echo [INFO] Testing connection (this may take some time)...
ssh -o ConnectTimeout=0 -i "%KEY_PATH%" %NETID%@irc.mlds.northwestern.edu "touch ~/golden-ticket && ls -la ~/golden-ticket && rm ~/golden-ticket"

if %ERRORLEVEL% equ 0 (
    echo [SUCCESS] Connection test passed. Your SSH key is working correctly
    
    :: Log successful setup to shared folder
    echo [INFO] Logging successful setup
    for /f "tokens=2 delims==." %%a in ('wmic OS Get LocalDateTime /value') do set "TIMESTAMP=%%a"
    set "TIMESTAMP=!TIMESTAMP:~0,4!-!TIMESTAMP:~4,2!-!TIMESTAMP:~6,2! !TIMESTAMP:~8,2!:!TIMESTAMP:~10,2!:!TIMESTAMP:~12,2!"
    
    :: Get hostname
    for /f "tokens=*" %%a in ('hostname') do set "HOSTNAME=%%a"
    
    :: Get a unique filename based on timestamp
    set "LOG_FILENAME=%NETID%_!TIMESTAMP:~0,4!!TIMESTAMP:~5,2!!TIMESTAMP:~8,2!!TIMESTAMP:~11,2!!TIMESTAMP:~14,2!!TIMESTAMP:~17,2!.log"
    set "LOG_FILENAME=!LOG_FILENAME: =!"
    set "LOG_FILENAME=!LOG_FILENAME::=!"
    set "LOG_FILENAME=!LOG_FILENAME:-=!"
    
    :: Attempt to log the successful setup
    ssh -i "%KEY_PATH%" %NETID%@irc.mlds.northwestern.edu "echo [!TIMESTAMP!] Setup successful from !HOSTNAME! >> /nfs/home/shared/migration/!LOG_FILENAME!" >nul 2>&1
    
    if %ERRORLEVEL% equ 0 (
        echo [SUCCESS] Setup logged successfully
    ) else (
        echo [WARNING] Could not write to log file, but setup was successful
    )
) else (
    echo [ERROR] Connection test failed. Please check the following:
    echo [INFO] 1. Ensure you entered the correct NetID
    echo [INFO] 2. Make sure the NFS server is accessible
    echo [INFO] 3. Verify that your account is properly set up on the server
    echo [INFO] 4. Check if the server hostname 'wolf.analytics.private' resolves correctly
    
    :: Try with full hostname as a fallback
    echo [INFO] Trying connection with full hostname as a fallback...
    ssh -i "%KEY_PATH%" %NETID%@irc.mlds.northwestern.edu "touch ~/golden-ticket && ls -la ~/golden-ticket && rm ~/golden-ticket"
    
    if %ERRORLEVEL% equ 0 (
        echo [SUCCESS] Connection successful using full hostname. Your SSH key works, but there might be an issue with your SSH config.
        
        :: Log successful setup to shared folder
        echo [INFO] Logging successful setup
        for /f "tokens=2 delims==." %%a in ('wmic OS Get LocalDateTime /value') do set "TIMESTAMP=%%a"
        set "TIMESTAMP=!TIMESTAMP:~0,4!-!TIMESTAMP:~4,2!-!TIMESTAMP:~6,2! !TIMESTAMP:~8,2!:!TIMESTAMP:~10,2!:!TIMESTAMP:~12,2!"
        
        :: Get hostname
        for /f "tokens=*" %%a in ('hostname') do set "HOSTNAME=%%a"
        
        :: Get a unique filename based on timestamp
        set "LOG_FILENAME=%NETID%_!TIMESTAMP:~0,4!!TIMESTAMP:~5,2!!TIMESTAMP:~8,2!!TIMESTAMP:~11,2!!TIMESTAMP:~14,2!!TIMESTAMP:~17,2!.log"
        set "LOG_FILENAME=!LOG_FILENAME: =!"
        set "LOG_FILENAME=!LOG_FILENAME::=!"
        set "LOG_FILENAME=!LOG_FILENAME:-=!"
        
        :: Attempt to log the successful setup
        ssh -i "%KEY_PATH%" %NETID%@irc.mlds.northwestern.edu "echo [!TIMESTAMP!] Setup successful from !HOSTNAME! >> /nfs/home/shared/migration/!LOG_FILENAME!" >nul 2>&1
        
        if %ERRORLEVEL% equ 0 (
            echo [SUCCESS] Setup logged successfully
        ) else (
            echo [WARNING] Could not write to log file, but setup was successful
        )
    ) else (
        echo [ERROR] Connection failed with full hostname as well. Please contact MLDS support for assistance.
    )
)

echo [INFO] Setup complete!
echo [INFO] CAVEAT! The wolf server is not yet transitioned to local login!!
echo [INFO] Once the server *IS* transitioned to local login, simply type: ssh %SERVER_NICKNAME%
echo [INFO] But if you try this now, it will still be slow or potentially fail.

:: Add a pause at the end to keep the window open
echo.
echo Press any key to exit...
pause >nul

:: End of script
endlocal
exit /b 0