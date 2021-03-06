#
#  Copyright 2009-2013 MongoDB, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#


use strict;
use warnings;
use Test::More 0.96;
use Test::Fatal;

use Data::Dumper;

use MongoDB::Timestamp; # needed if db is being run as master
use MongoDB;

use lib "t/lib";
use MongoDBTest qw/skip_unless_mongod build_client server_type server_version/;

skip_unless_mongod();

plan skip_all => "Not supported on Atlas Free Tier"
    if $ENV{ATLAS_PROXY};

my $conn = build_client();
my $server_type = server_type( $conn );
my $server_version = server_version( $conn );

my $server_status_res = $conn->send_admin_command([serverStatus => 1]);
my $storage_engine = $server_status_res->{output}{storageEngine}{name} || '';
plan skip_all => "fsync not supported for inMemory storage engine"
    if $storage_engine =~ qr/inMemory/;

my $ret;

# Test normal fsync.
subtest "normal fsync" => sub {
    $ret = $conn->fsync();
    is($ret->{ok},              1, "fsync returned 'ok' => 1");
};

# Test fsync with lock.
subtest "fsync with lock" => sub {
    plan skip_all => "lock not supported through mongos"
        if $server_type eq 'Mongos';

    # Lock
    $ret = $conn->fsync({lock => 1});
    is($ret->{ok},              1, "fsync + lock returned 'ok' => 1");

    # Check the lock.
    if ($server_version <= v3.1.0) {
        $ret = $conn->get_database('admin')->get_collection('$cmd.sys.inprog')->find_one();
    }
    else {
        $ret = $conn->send_admin_command([currentOp => 1]);
        $ret = $ret->{output};
    }
    is($ret->{fsyncLock}, 1, "MongoDB is locked.");

    # Unlock 
    $ret = $conn->fsync_unlock(); Dumper($ret);
    is($ret->{ok}, 1, "Got 'ok' => 1 from unlock command.");

    # Check the lock was released.
    if ($server_version <= v3.1.0) {
        $ret = $conn->get_database('admin')->get_collection('$cmd.sys.inprog')->find_one();
    }
    else {
        $ret = $conn->send_admin_command([currentOp => 1]);
        $ret = $ret->{output};
    }
    ok(! $ret->{fsyncLock}, "MongoDB is no longer locked.");

};

done_testing;
