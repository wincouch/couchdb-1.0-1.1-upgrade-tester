#!/bin/sh -ex
# This script tests upgrading CouchDB from 1.0 to 1.1
# See https://issues.apache.org/jira/browse/COUCHDB-951 for details

# Expects to run from it's source dir
# Depends on: All CouchDB dependencies, openssl
# Usage: 
# $ ./run.sh


# Setup environment
CWD=`pwd`
cd /tmp # nothing lasts forever
TESTDIR=couchdb-upgrade-1.0-to-1.1
rm -rf $TESTDIR # we may have been here before, start over
mkdir -p $TESTDIR
cd $TESTDIR

OPENSSL=`which openssl`
if [ -z "$OPENSSL" ]; then
  echo "Can’t find md5 or openssl, exiting."
  exit 1
fi

mkdir -p src
mkdir -p 1.0
mkdir -p 1.1

cd src

git clone git://git.apache.org/couchdb.git --depth=1 # be gentle

cd couchdb

# build 1.0.x
git checkout 1.0.x
./bootstrap
./configure --prefix=/tmp/$TESTDIR/1.0
make -j4 # woooosh
make install

# build 1.1.x
git checkout 1.1.x
./bootstrap
./configure --prefix=/tmp/$TESTDIR/1.1
make -j4 # woooosh
make install

cd ../..
cd 1.0

# launch 1.0
# disable delayed commits, so we can copy the database file from under the
# running couch instance after our curl returns
# TODO: could be a curl config call
echo "[couchdb]" > llocal.ini
echo "delayed_commits=false" >> llocal.ini
echo "" >> llocal.ini
./bin/couchdb -b -a llocal.ini

cd ..
cd 1.1

# launch 1.1
# disable delayed commits, so we can copy the database file from under the
# running couch instance after our curl returns
# TODO: could be a curl config call
echo "[couchdb]" > llocal.ini
echo "delayed_commits=false" >> llocal.ini

# set port number to +1 so both couches can run in parallel
echo "[httpd]" >> llocal.ini
echo "port=5985" >> llocal.ini
echo "" >> llocal.ini
./bin/couchdb -b -a llocal.ini

# wait for couches to boot, you may have to adjust this on slower systems
sleep 2
cd ..

# create test db in 1.0

COUCH10=http://127.0.0.1:5984
curl -X PUT $COUCH10/test-db
curl -X PUT $COUCH10/test-db/test-doc/attachment.txt \
  -H "Content-Type: text/plain" \
  -d "My Hovercraft is full of eels"

# test binary files at 2k, 4k and 8k
for bin in $CWD/attachments/*.bin; do
  # store binary
  binbasename=`basename $bin`
  binname=`basename -s .bin $bin`
  curl -X PUT $COUCH10/test-db/test-doc-$binname/$binbasename \
  -H "Content-Type: application/octet-stream" \
  --data-binary @$bin
done

# copy test db to 1.1
cp 1.0/var/lib/couchdb/test-db.couch 1.1/var/lib/couchdb/test-db.couch

# compact with 1.1
COUCH11=http://127.0.0.1:5985
curl -X POST $COUCH11/test-db/_compact -H "Content-Type: application/json"

# validate test db
TEST_PASSED=true

RESULT=`curl $COUCH11/test-db/test-doc/attachment.txt`
if [ "$RESULT" != "My Hovercraft is full of eels" ]; then
  TEST_PASSED=false
fi

mkdir attachment-results
cd attachment-results
for bin in $CWD/attachments/*.bin; do
  binbasename=`basename $bin`
  binname=`basename -s .bin $bin`
  curl -O $COUCH11/test-db/test-doc-$binname/$binbasename
  BEFORE=`$OPENSSL sha $bin | awk '{print $2}'`
  AFTER=`$OPENSSL sha $binbasename | awk '{print $2}'`
  if [ "$BEFORE" !=  "$AFTER" ]; then
    TEST_PASSED=false
  fi
done

cd ..

# shutdown couches

cd /tmp/$TESTDIR

cd 1.0
./bin/couchdb -d

cd ..
cd 1.1
./bin/couchdb -d

# resultin
if [ "$TEST_PASSED" = "false" ]; then
  echo "UPGRADE FAILED"
else
  echo "UPGRADE PASSED"
fi

# DONE
