@ECHO off
SETLOCAL EnableDelayedExpansion

IF NOT "%systemdrive%"=="X:" (ECHO:
							  ECHO This CMD script should only be run in Windows Recovery Environment.
							  ECHO:
							  ECHO You can find detailed instructions at the link below:
							  ECHO https://www.revouninstaller.com/online-manual/restore-full-registry-backup/
							  ECHO:
							  ECHO ======================
							  ECHO Press any key to exit.
							  ECHO ======================
							  PAUSE >nul
							  EXIT
							  )

SET profileIndex=0
SET profileMatchIndex=0
SET "choiceOptions="
SET "choiceMatchOptions="
SET "rupRestorePath="

FOR %%A IN (C D E F G H I J K L M N O P Q R S T U V W Y Z) DO @IF EXIST %%A:\Windows\WinSxS SET sd=%%A
START /WAIT REG LOAD HKLM\TempSys %sd%:\Windows\System32\config\SYSTEM >nul
FOR /F "tokens=3" %%A IN ('REG QUERY "HKLM\TempSys\ControlSet001\Control\ComputerName\ComputerName" /V ComputerName ^|%sd%:\Windows\System32\findstr.exe /ri "REG_SZ"') DO SET cn=%%A
IF DEFINED rupRestorePath (GOTO useProvidedBackup) ELSE (GOTO searchForBackup)

:useProvidedBackup
FOR %%A IN (C D E F G H I J K L M N O P Q R S T U V W X Y Z) DO @IF EXIST "%%A:%rupRestorePath%\" (SET rd=%%A) ELSE (GOTO searchForBackup)
CD /D "%rd%:%rupRestorePath%
FOR /F "tokens=*" %%A IN ('DIR "%rd%:%rupRestorePath%" /AD /B') DO (IF EXIST "%rd%:%rupRestorePath%\%%A\RegBackup\Last" (SET /A profileIndex+=1
																														 SET "profile[!profileIndex!]=%%A"
																														 SET choiceOptions=!choiceOptions!!profileIndex!
																														 ))
IF %profileIndex% EQU 0 GOTO noBackups
IF %profileIndex% EQU 1 GOTO oneBackup
IF %profileIndex% GEQ 2 GOTO multipleBackups

:searchForBackup
IF EXIST "%CD%\Data" (CD Data) ELSE (CD ..\Data)
SET "foundRUPPpath=%CD%"
FOR /F "tokens=*" %%A IN ('DIR /AD /B') DO (IF EXIST "%%A\RegBackup\Last" (SET /A profileIndex+=1
																		   SET "profile[!profileIndex!]=%%A"
																		   SET choiceOptions=!choiceOptions!!profileIndex!
																		   ))
IF %profileIndex% EQU 0 GOTO noBackups
IF %profileIndex% EQU 1 GOTO oneBackup
IF %profileIndex% GEQ 2 GOTO multipleBackups

:noBackups
CLS
ECHO:
ECHO No full Registry backups were found.
GOTO reboot

:oneBackup
FOR /F "tokens=1 delims=_" %%A IN ("%profile[1]%") DO (IF "%%A"=="%cn%" (GOTO oneBackupA) ELSE (GOTO oneBackupB))

:oneBackupA
CLS
ECHO:
ECHO Only one Registry backup was found. The computer name for the backup matches the name of the current computer.
ECHO:
ECHO %profile[1]%
ECHO:
%sd%:\Windows\System32\choice.exe /C yc /N /M "To confirm the restoration, type [y]; to cancel, type [c]: "
IF %ERRORLEVEL% EQU 1 (IF DEFINED foundRUPPpath (CD /D "%foundRUPPpath%\%profile[1]%\RegBackup\Last") ELSE (CD /D "%rd%:%rupRestorePath%\%profile[1]%\RegBackup\Last")
					   GOTO runRestore
				       )
IF %ERRORLEVEL% EQU 2 (EXIT /B
					   GOTO reboot
					   )

:oneBackupB
CLS
ECHO:
ECHO Only one Registry backup was found. The computer name for the backup does *NOT* match the name of the current computer.
ECHO:
ECHO 1. %profile[1]%
ECHO:
%sd%:\Windows\System32\choice.exe /C yc /N /M "To confirm the restoration, type [Y]; to cancel, type [C]."
IF %ERRORLEVEL% EQU 1 (IF DEFINED foundRUPPpath (CD /D "%foundRUPPpath%\%profile[1]%\RegBackup\Last") ELSE (CD /D "%rd%:%rupRestorePath%\%profile[1]%\RegBackup\Last")
					   GOTO runRestore
				       )
IF %ERRORLEVEL% EQU 2 (EXIT /B
					   GOTO reboot
					   )

:multipleBackups
FOR /F "tokens=1 delims=_" %%A IN ('DIR /AD /B') DO (IF "%%A"=="%cn%" (SET matchExists=true))
IF "%matchExists%"=="true" (GOTO multipleBackupsA) ELSE (GOTO multipleBackupsB)

:multipleBackupsA
FOR /F "tokens=*" %%A IN ('DIR /AD /B %cn%*') DO (SET /A profileMatchIndex+=1
												  SET "profileMatch[!profileMatchIndex!]=%%A"
												  SET choiceMatchOptions=!choiceMatchOptions!!profileMatchIndex!
												  )
CLS
ECHO:
ECHO The following Registry backups match the current computer:
ECHO:
FOR /L %%A IN (1,1,!profileMatchIndex!) DO (
				ECHO %%A. !profileMatch[%%A]!
				)
ECHO:
%sd%:\Windows\System32\choice.exe /C:c!choiceMatchOptions! /N /M "Type the number of the backup you wish to restore; to cancel, type [C]."
IF DEFINED foundRUPPpath (CD /D "%foundRUPPpath%\!profileMatch[%ERRORLEVEL%]!\RegBackup\Last") ELSE (CD /D "%rd%:%rupRestorePath%\!profileMatch[%ERRORLEVEL%]!\RegBackup\Last")
GOTO runRestore

:multipleBackupsB
CLS
ECHO:
ECHO No Registry backups matching the current computer were found.
GOTO reboot

:runRestore
(FOR /F "delims=" %%i IN (Restore.dat) DO (
	SET "line=%%i"
	SET "line=!line:C:\=%sd%:\!"
    ECHO(!line!
))>"Restore_tmp.bat"
CALL Restore_tmp.bat
DEL /Q Restore_tmp.bat
CLS
GOTO reboot

:reboot
ECHO:
ECHO ===================================
ECHO Press any key to reboot the system.
ECHO ===================================
PAUSE >nul
%sd%:\Windows\System32\shutdown.exe /r /t 0