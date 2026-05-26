@ECHO off
reg Query "HKLM\Hardware\Description\System\CentralProcessor\0" | find /i "x86" > NUL && set OS=32bit || set OS=64bit

IF %OS%==32bit CAll "x86\RUPPrestore.cmd"
IF %OS%==64bit CALL "x64\RUPPrestore.cmd"