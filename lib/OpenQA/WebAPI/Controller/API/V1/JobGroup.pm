# Copyright (C) 2016 SUSE LLC
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
# with this program; if not, see <http://www.gnu.org/licenses/>.

package OpenQA::WebAPI::Controller::API::V1::JobGroup;
use Mojo::Base 'Mojolicious::Controller';
use OpenQA::Schema::Result::JobGroups;

sub list {
    my $self = shift;

    my $group_id = $self->param('group_id');
    my $job_groups;
    if ($group_id) {
        $job_groups = $self->db->resultset('JobGroups')->search({id => $group_id});
        return $self->render(json => {error => "Job group $group_id does not exist"}) unless $job_groups;
    }
    else {
        $job_groups = $self->db->resultset('JobGroups');
    }

    my @results;
    while (my $group = $job_groups->next) {
        push(
            @results,
            {
                id                             => $group->id,
                name                           => $group->name,
                parent_id                      => $group->parent_id,
                size_limit_gb                  => $group->size_limit_gb,
                keep_logs_in_days              => $group->keep_logs_in_days,
                keep_important_logs_in_days    => $group->keep_important_logs_in_days,
                keep_results_in_days           => $group->keep_results_in_days,
                keep_important_results_in_days => $group->keep_important_results_in_days,
                default_priority               => $group->default_priority,
                sort_order                     => $group->sort_order,
                description                    => $group->description
            });
    }
    $self->render(json => \@results);
}

sub create {
    # TODO
}

sub update {
    my ($self) = @_;

    my $group_id = $self->param('group_id');
    my $group    = $self->db->resultset('JobGroups')->find($group_id);
    return $self->render(json => {error => "Job group $group_id does not exist"}) unless $group;

    my %updates;
    for my $param (qw(name parent_id size_limit_gb keep_logs_in_days keep_important_logs_in_days keep_results_in_days keep_important_results_in_days default_priority sort_order description)) {
        my $value = $self->param($param);
        $updates{$param} = $value if defined($value);
    }

    my $res = $group->update(\%updates);
    return $self->render(json => {error => "Specified job group $group_id exist but unable to update, though"}) unless $res;
    $self->render(json => {id => $res->id});
}

sub delete {
    # TODO
}

1;
