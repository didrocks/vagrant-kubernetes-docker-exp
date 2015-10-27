#!/bin/bash -e

GOPATH=$(dirname $(readlink -f $0))
export GOBIN=$GOPATH/bin

cd $GOPATH
pushd src/server 1>/dev/null
go get
popd 1>/dev/null
go install server
