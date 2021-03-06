# Copyright (C) 2014-2016 SUSE LLC
# Copyright (C) 2016 Red Hat
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

BEGIN {
    unshift @INC, 'lib';
}

use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use Test::Warnings ':all';
use OpenQA::Test::Case;
use OpenQA::Client;
use Mojo::IOLoop;
use Data::Dump;

use OpenQA::IPC;
use OpenQA::WebSockets;
use OpenQA::Scheduler;

OpenQA::Test::Case->new->init_data;

my $t = Test::Mojo->new('OpenQA::WebAPI');

# XXX: Test::Mojo loses it's app when setting a new ua
# https://github.com/kraih/mojo/issues/598
my $app = $t->app;
$t->ua(OpenQA::Client->new(apikey => 'PERCIVALKEY02', apisecret => 'PERCIVALSECRET02')->ioloop(Mojo::IOLoop->singleton));
$t->app($app);

sub lj {
    return unless $ENV{HARNESS_IS_VERBOSE};
    my $ret  = $t->get_ok('/api/v1/jobs')->status_is(200);
    my @jobs = @{$ret->tx->res->json->{jobs}};
    for my $j (@jobs) {
        printf "%d %-10s %s@%s\n", $j->{id}, $j->{state}, $j->{name}, $j->{settings}->{MACHINE};
    }
}

sub find_job {
    my ($jobs, $newids, $name, $machine) = @_;
    my $ret;
    for my $j (@$jobs) {
        if ($j->{settings}->{TEST} eq $name && $j->{settings}->{MACHINE} eq $machine) {
            # take the last if there are more than one
            $ret = $j;
        }
    }

    return undef unless defined $ret;

    for my $id (@$newids) {
        return $ret if $id == $ret->{id};
    }
    return undef;
}

sub schedule_iso {
    my ($args, $status) = @_;
    $status //= 200;
    my $ret = $t->post_ok('/api/v1/isos', form => $args)->status_is($status);
    return $ret->tx->res;
}

# create Test DBus bus and service for fake WebSockets and Scheduler call
my $ipc = OpenQA::IPC->ipc('', 1);
my $ws  = OpenQA::WebSockets->new;
my $sh  = OpenQA::Scheduler->new;

my $ret;

my $iso = 'openSUSE-13.1-DVD-i586-Build0091-Media.iso';

$ret = $t->get_ok('/api/v1/jobs/99927')->status_is(200);
is($ret->tx->res->json->{job}->{state}, 'scheduled', 'job 99927 is scheduled');
$ret = $t->get_ok('/api/v1/jobs/99928')->status_is(200);
is($ret->tx->res->json->{job}->{state}, 'scheduled', 'job 99928 is scheduled');
$ret = $t->get_ok('/api/v1/jobs/99963')->status_is(200);
is($ret->tx->res->json->{job}->{state}, 'running', 'job 99963 is running');

$ret = $t->get_ok('/api/v1/jobs/99981')->status_is(200);
is($ret->tx->res->json->{job}->{state}, 'cancelled', 'job 99981 is cancelled');

$ret = $t->post_ok('/api/v1/jobs/99981/restart')->status_is(200);

$ret = $t->get_ok('/api/v1/jobs/99981')->status_is(200);
my $clone99981 = $ret->tx->res->json->{job}->{clone_id};

$ret = $t->get_ok("/api/v1/jobs/$clone99981")->status_is(200);
is($ret->tx->res->json->{job}->{state}, 'scheduled', 'job $clone99981 is scheduled');

lj;

my @tasks;
@tasks = $t->app->db->resultset("GruTasks")->search({taskname => 'download_asset'});
is(scalar @tasks, 0, 'we have no gru download tasks to start with');

# add a random comment on a scheduled but not started job so that this one
# later on is found as important and handled accordingly
$t->app->db->resultset("Jobs")->find(99928)->comments->create({text => 'any text', user_id => 99901});

# schedule the iso, this should not actually be possible. Only isos
# with different name should result in new tests...
my $expected = qr/START_AFTER_TEST=.* not found - check for typos and dependency cycles/;
my $res;
my @warnings = warnings { $res = schedule_iso({ISO => $iso, DISTRI => 'opensuse', VERSION => '13.1', FLAVOR => 'DVD', ARCH => 'i586', BUILD => '0091'}) };
is(scalar @warnings, 2, 'two warnings expected');
map { like($_, $expected) } @warnings;

is($res->json->{count}, 10, "10 new jobs created");
my @newids = @{$res->json->{ids}};
my $newid  = $newids[0];


$ret = $t->get_ok('/api/v1/jobs');
my @jobs = @{$ret->tx->res->json->{jobs}};

my $server_32       = find_job(\@jobs, \@newids, 'server',       '32bit');
my $client1_32      = find_job(\@jobs, \@newids, 'client1',      '32bit');
my $client2_32      = find_job(\@jobs, \@newids, 'client2',      '32bit');
my $advanced_kde_32 = find_job(\@jobs, \@newids, 'advanced_kde', '32bit');
my $kde_32          = find_job(\@jobs, \@newids, 'kde',          '32bit');
my $textmode_32     = find_job(\@jobs, \@newids, 'textmode',     '32bit');

is_deeply($client1_32->{parents}, {Parallel => [$server_32->{id}], Chained => []}, "server_32 is only parent of client1_32");
is_deeply($client2_32->{parents}, {Parallel => [$server_32->{id}], Chained => []}, "server_32 is only parent of client2_32");
is_deeply($server_32->{parents},  {Parallel => [],                 Chained => []}, "server_32 has no parents");
is($kde_32, undef, "kde is not created for 32bit machine");
is_deeply($advanced_kde_32->{parents}, {Parallel => [], Chained => [$textmode_32->{id}]}, "textmode_32 is only parent of advanced_kde_32");    # kde is not defined for 32bit machine

my $server_64       = find_job(\@jobs, \@newids, 'server',       '64bit');
my $client1_64      = find_job(\@jobs, \@newids, 'client1',      '64bit');
my $client2_64      = find_job(\@jobs, \@newids, 'client2',      '64bit');
my $advanced_kde_64 = find_job(\@jobs, \@newids, 'advanced_kde', '64bit');
my $kde_64          = find_job(\@jobs, \@newids, 'kde',          '64bit');
my $textmode_64     = find_job(\@jobs, \@newids, 'textmode',     '64bit');

is_deeply($client1_64->{parents}, {Parallel => [$server_64->{id}], Chained => []}, "server_64 is only parent of client1_64");
is_deeply($client2_64->{parents}, {Parallel => [$server_64->{id}], Chained => []}, "server_64 is only parent of client2_64");
is_deeply($server_64->{parents},  {Parallel => [],                 Chained => []}, "server_64 has no parents");
is($textmode_64, undef, "textmode is not created for 64bit machine");
is_deeply($advanced_kde_64->{parents}, {Parallel => [], Chained => [$kde_64->{id}]}, "kde_64 is only parent of advanced_kde_64");    # textmode is not defined for 64bit machine

is($server_32->{group_id}, 1001, 'server_32 part of opensuse group');
is($server_64->{group_id}, 1001, 'server_64 part of opensuse group');

is($advanced_kde_32->{settings}->{PUBLISH_HDD_1}, 'opensuse-13.1-i586-kde-qemu32.qcow2', "variable expansion");
is($advanced_kde_64->{settings}->{PUBLISH_HDD_1}, 'opensuse-13.1-i586-kde-qemu64.qcow2', "variable expansion");

lj;

subtest 'old tests are cancelled unless they are marked as important' => sub {
    $ret = $t->get_ok('/api/v1/jobs/99927')->status_is(200);
    is($ret->tx->res->json->{job}->{state}, 'cancelled', 'job 99927 is cancelled');
    $ret = $t->get_ok('/api/v1/jobs/99928')->status_is(200);
    is($ret->tx->res->json->{job}->{state}, 'scheduled', 'job 99928 is marked as important and therefore preserved');
    $ret = $t->get_ok('/api/v1/jobs/99963')->status_is(200);
    is($ret->tx->res->json->{job}->{state}, 'running', 'job 99963 is running');
};

# make sure unrelated jobs are not cancelled
$ret = $t->get_ok("/api/v1/jobs/$clone99981")->status_is(200);
is($ret->tx->res->json->{job}->{state}, 'scheduled', "job $clone99981 is still scheduled");

# ... and we have a new test
$ret = $t->get_ok("/api/v1/jobs/$newid")->status_is(200);
is($ret->tx->res->json->{job}->{state}, 'scheduled', "new job $newid is scheduled");

# cancel the iso
$ret = $t->post_ok("/api/v1/isos/$iso/cancel")->status_is(200);

$ret = $t->get_ok("/api/v1/jobs/$newid")->status_is(200);
is($ret->tx->res->json->{job}->{state}, 'cancelled', "job $newid is cancelled");

# make sure we can't post invalid parameters
$res = schedule_iso({iso => $iso, tests => "kde/usb"}, 400);

# handle list of tests
$res = schedule_iso(
    {
        ISO     => $iso,
        DISTRI  => 'opensuse',
        VERSION => '13.1',
        FLAVOR  => 'DVD',
        ARCH    => 'i586',
        TEST    => 'server,kde,textmode',
        BUILD   => '0091'
    },
    200
);

is($res->json->{count}, 4, "4 new jobs created (one twice for both machine types)");

# delete the iso
# can not do as operator
$ret = $t->delete_ok("/api/v1/isos/$iso")->status_is(403);
# switch to admin and continue
$app = $t->app;
$t->ua(OpenQA::Client->new(apikey => 'ARTHURKEY01', apisecret => 'EXCALIBUR')->ioloop(Mojo::IOLoop->singleton));
$t->app($app);
$ret = $t->delete_ok("/api/v1/isos/$iso")->status_is(200);
# now the jobs should be gone
$ret = $t->get_ok('/api/v1/jobs/$newid')->status_is(404);

subtest 'jobs belonging to important builds are not cancelled by new iso post' => sub {
    $ret = $t->get_ok('/api/v1/jobs/99963')->status_is(200);
    is($ret->tx->res->json->{job}->{state}, 'running', 'job in build 0091 running');
    my $tag = 'tag:0091:important';
    $t->app->db->resultset("JobGroups")->find(1001)->comments->create({text => $tag, user_id => 99901});
    @warnings = warnings { $res = schedule_iso({ISO => $iso, DISTRI => 'opensuse', VERSION => '13.1', FLAVOR => 'DVD', ARCH => 'i586', BUILD => '0091'}) };
    is(scalar @warnings,    2,  'two warnings expected');
    is($res->json->{count}, 10, '10 jobs created');
    $ret = $t->get_ok('/api/v1/jobs/99992')->status_is(200);
    is($ret->tx->res->json->{job}->{state}, 'scheduled');
    @warnings = warnings { $res = schedule_iso({ISO => $iso, DISTRI => 'opensuse', VERSION => '13.1', FLAVOR => 'DVD', ARCH => 'i586', BUILD => '0092'}) };
    is(scalar @warnings, 2, 'two warnings expected');
    $ret = $t->get_ok('/api/v1/jobs/99992')->status_is(200);
    is($ret->tx->res->json->{job}->{state}, 'scheduled', 'job in old important build still scheduled');
    @warnings = warnings { $res = schedule_iso({ISO => $iso, DISTRI => 'opensuse', VERSION => '13.1', FLAVOR => 'DVD', ARCH => 'i586', BUILD => '0093'}) };
    is(scalar @warnings, 2, 'two warnings expected');
    $ret = $t->get_ok('/api/v1/jobs?state=scheduled');
    my @jobs = @{$ret->tx->res->json->{jobs}};
    lj;
    ok(!grep({ $_->{settings}->{BUILD} =~ '009[2]' } @jobs), 'no jobs from intermediate, not-important build');
    is(scalar @jobs, 21, 'only the important jobs, jobs from the current build and the important build are scheduled');
};

$t->app->config->{global}->{download_domains} = 'localhost';

my $rsp;

# Schedule download of an existing ISO
@warnings = warnings { $rsp = schedule_iso({DISTRI => 'opensuse', VERSION => '13.1', FLAVOR => 'DVD', ARCH => 'i586', ISO_URL => 'http://localhost/openSUSE-13.1-DVD-i586-Build0091-Media.iso'}) };
map { like($_, $expected, 'expected warning') } @warnings;
is($t->app->db->resultset("GruTasks")->search({taskname => 'download_asset'}), 0, 'gru task should not be created');

# Schedule download of an existing HDD for extraction
@warnings = warnings { $rsp = schedule_iso({DISTRI => 'opensuse', VERSION => '13.1', FLAVOR => 'DVD', ARCH => 'i586', HDD_1_DECOMPRESS_URL => 'http://localhost/openSUSE-13.1-x86_64.hda.xz'}) };
map { like($_, $expected, 'expected warning') } @warnings;
is($t->app->db->resultset("GruTasks")->search({taskname => 'download_asset'}), 0, 'gru task should not be created');

# Schedule download of a non-existing ISO
@warnings = warnings { $rsp = schedule_iso({DISTRI => 'opensuse', VERSION => '13.1', FLAVOR => 'DVD', ARCH => 'i586', ISO_URL => 'http://localhost/nonexistent.iso'}) };
is($rsp->json->{count}, 10, 'a regular ISO post creates the expected number of jobs');
map { like($_, $expected, 'expected warning') } @warnings;
is($t->app->db->resultset("GruTasks")->search({taskname => 'download_asset'}), 1, 'gru task should be created');

# Schedule download of a non-existing HDD
@warnings = warnings { $rsp = schedule_iso({DISTRI => 'opensuse', VERSION => '13.1', FLAVOR => 'DVD', ARCH => 'i586', HDD_1_DECOMPRESS_URL => 'http://localhost/nonexistent.hda.xz'}) };
is($rsp->json->{count}, 10, 'a regular ISO post creates the expected number of jobs');
map { like($_, $expected, 'expected warning') } @warnings;
is($t->app->db->resultset("GruTasks")->search({taskname => 'download_asset'}), 2, 'gru task should be created');

# Using non-asset _URL does not create gru job and schedule jobs
@warnings = warnings { $rsp = schedule_iso({DISTRI => 'opensuse', VERSION => '13.1', FLAVOR => 'DVD', ARCH => 'i586', NO_ASSET_URL => 'http://localhost/nonexistent.iso'}) };
map { like($_, $expected, 'expected warning') } @warnings;
is($rsp->json->{count}, 10, 'a regular ISO post creates the expected number of jobs');
is($t->app->db->resultset("GruTasks")->search({taskname => 'download_asset'}), 2, 'no additional gru task should be created');

# Using asset _URL but without filename extractable from URL create warning in log file, jobs, but no gru job
@warnings = warnings { $rsp = schedule_iso({DISTRI => 'opensuse', VERSION => '13.1', FLAVOR => 'DVD', ARCH => 'i586', ISO_URL => 'http://localhost'}) };
map { like($_, $expected, 'expected warning') } @warnings;
is($rsp->json->{count}, 10, 'a regular ISO post creates the expected number of jobs');
is($t->app->db->resultset("GruTasks")->search({taskname => 'download_asset'}), 2, 'no additional gru task should be created');

# Using asset _URL outside of whitelist will yield 403
@warnings = warnings { $rsp = schedule_iso({DISTRI => 'opensuse', VERSION => '13.1', FLAVOR => 'DVD', ARCH => 'i586', ISO_URL => 'http://adamshost/nonexistent.iso'}, 403) };
map { like($_, $expected, 'expected warning') } @warnings;
is($rsp->message, 'Asset download requested from non-whitelisted host adamshost');
is($t->app->db->resultset("GruTasks")->search({taskname => 'download_asset'}), 2, 'no additional gru task should be created');

# Using asset _DECOMPRESS_URL outside of whitelist will yield 403
@warnings = warnings { $rsp = schedule_iso({DISTRI => 'opensuse', VERSION => '13.1', FLAVOR => 'DVD', ARCH => 'i586', HDD_1_DECOMPRESS_URL => 'http://adamshost/nonexistent.hda.xz'}, 403) };
map { like($_, $expected, 'expected warning') } @warnings;
is($rsp->message, 'Asset download requested from non-whitelisted host adamshost');
is($t->app->db->resultset("GruTasks")->search({taskname => 'download_asset'}), 2, 'no additional gru task should be created');

# Using asset _URL will automatically create parameter without _URL
@warnings = warnings { $rsp = schedule_iso({DISTRI => 'opensuse', VERSION => '13.1', FLAVOR => 'DVD', ARCH => 'i586', ISO => $iso, KERNEL_URL => 'http://localhost/vmlinuz'}) };
map { like($_, $expected, 'expected warning') } @warnings;

$newid = @{$ret->tx->res->json->{ids}}[0];
$ret   = $t->get_ok("/api/v1/jobs/$newid")->status_is(200);
is($ret->tx->res->json->{job}->{settings}->{KERNEL}, 'vmlinuz', "parameter KERNEL is correctly set from KERNEL_URL");

# Having parameter without _URL and the same with _URL will not overwrite it
@warnings = warnings { $rsp = schedule_iso({DISTRI => 'opensuse', VERSION => '13.1', FLAVOR => 'DVD', ARCH => 'i586', ISO => $iso, KERNEL => 'vmlinuz.img.20160516', KERNEL_URL => 'http://localhost/vmlinuz'}) };
map { ok($_ =~ $expected, 'expected warning') } @warnings;

$newid = @{$ret->tx->res->json->{ids}}[0];
$ret   = $t->get_ok("/api/v1/jobs/$newid")->status_is(200);
is($ret->tx->res->json->{job}->{settings}->{KERNEL}, 'vmlinuz.img.20160516', "parameter KERNEL is not overwritten when KERNEL_URL is set");

done_testing();
