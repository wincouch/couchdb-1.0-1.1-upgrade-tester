:: This script tests upgrading CouchDB from 1.0 to 1.1
:: See https://issues.apache.org/jira/browse/COUCHDB-951 for details
:: Released under same licence as CouchDB
:: Purloined and Pillaged from jan@
:: original source https://github.com/janl/couchdb-1.0-1.1-upgrade-tester
:: Includes OpenSSL, cURL, and rdfc.exe binaries
:: because on Windows, There is Nothing Upon Which You Can Depend
:: all couches listen on 0.0.0.0 ports 5983,5984,5985 resp for 0.11,1.0.2,1.1.0

:: move to script root; this is where we will run
pushd %~dp0
setlocal
:: keep our binaries ahead of others
path=%~dp0\bin;%path%
:: setup erlang for each couch flava
::for /d %%i in (1*) do @echo %%i && pushd %~dp0\%%i && install.exe -S && popd

:: launch 1.0
:: port is 5984, delayed_commits already set
set onedotoh=1.0.2_R14B02_COUCHDB-963
start /min %~dp0\%OneDotOh%\bin\couchdb.bat
set couch10=http://127.0.0.1:5984

:: launch 1.1
:: port is 5985, delayed_commits already set
set onedotone=1.1.0a33f7a1b-git_otp_R14B02
start /min %~dp0\%OneDotOne%\bin\couchdb.bat
set couch11=http://127.0.0.1:5985

:: get ready
rd /s/q attachments
mkdir attachments
pushd attachments
set SIZES=1024 2048 3072 4095 4096 4097 8191 8192 8193 1048576 10485760 20971520 26214400 52428800 78643200 104857600
for %%i in (%sizes%) do rdfc %%i %%i
openssl sha * > ..\attachments.sha
popd

:: make database
curl -X PUT %couch10%/test-db

for %%i in (%sizes%) do curl -X PUT %COUCH10%/test-db/test-doc-%%i/%%i -H "Content-Type: application/octet-stream"  --data-binary @attachments/%%i

:: copy test db to 1.1
xcopy /b %OneDotOh%\var\lib\couchdb\test-db.couch %OneDotOne%\var\lib\couchdb\ /y

:: compact with 1.1
curl -X POST %couch11%/test-db/_compact -H "Content-Type: application/json"

:: validate test db
rd /s/q results
mkdir results
pushd results
for %%i in (%sizes%) do curl -#O %couch11%/test-db/test-doc-%%i/%%i
openssl sha * > ..\results.sha
popd
:: do the dirty
diff -iwaq attachments.sha results.sha | findstr differ && echo UPGRADE FAILED
if ERRORLEVEL 0 echo UPGRADE PASSED

echo Are you Ready to Clean Up? Ctrl-C to abort
pause
:: shutdown couches & clean up
pskill werl
pskill erl
pskill epmd
del /f/s/q attachments\* results\* couch.log test-db.couch _replicator.couch _users.couch erl.ini
popd
endlocal
