package TPF::SoC;

use Moose;
use syntax 'function', 'method';
use DateTime;
use Config::Any;
use MooseX::Types::Moose 'ArrayRef', 'HashRef';
use MooseX::Types::Path::Class 'File';
use MooseX::Types::DateTime DateTime => { -as => 'DateTimeType' }, 'Duration';
use MooseX::Types::LoadableClass 'LoadableClass';
use MooseX::Types::Common::String 'NonEmptySimpleStr';
use TPF::SoC::Types qw(Student Report DateTimeSpan ReportAnalyser ReportAnalysis ISO8601DateTime);
use Bread::Board::Declare;
use namespace::autoclean;

has config_file => (
    is     => 'ro',
    isa    => File,
    coerce => 1,
);

has config => (
    is           => 'ro',
    isa          => HashRef,
    dependencies => ['config_file'],
    block        => fun ($s) {
        Config::Any->load_files({
            files   => [$s->param('config_file')],
            use_ext => 1,
        })->[0]->{
            $s->param('config_file')
        };
    },
);

has student_class => (
    is     => 'ro',
    isa    => LoadableClass,
    coerce => 1,
    value  => 'TPF::SoC::Student',
);

has student_fields => (
    is    => 'ro',
    isa   => ArrayRef[NonEmptySimpleStr],
    block => sub { [qw(nick name email project_title blog)] },
);

has student_parser => (
    is           => 'ro',
    isa          => 'TPF::SoC::RecordParser',
    dependencies => {
        fields       => 'student_fields',
        record_class => 'student_class',
    },
);

has students_fh => (
    is       => 'ro',
    required => 1,
);

has students => (
    is           => 'ro',
    isa          => HashRef[Student],
    lifecycle    => 'Singleton',
    dependencies => ['student_parser', 'students_fh'],
    block        => fun ($s) {
        return {
            map {
                ($_->nick => $_)
            } $s->param('student_parser')->parse_fh(
                $s->param('students_fh'),
            ),
        };
    },
);

has report_class => (
    is     => 'ro',
    isa    => LoadableClass,
    coerce => 1,
    value  => 'TPF::SoC::Report',
);

has report_fields => (
    is    => 'ro',
    isa   => ArrayRef[NonEmptySimpleStr],
    block => sub { [qw(student date url)] },
);

has report_args_mangler => (
    is           => 'ro',
    isa          => 'CodeRef',
    dependencies => ['students'],
    block        => fun ($s) {
        my $students = $s->param('students');
        fun ($args) {
            return {
                %{ $args },
                student => $students->{ $args->{student} },
            };
        }
    },
);

has report_parser => (
    is           => 'ro',
    isa          => 'TPF::SoC::RecordParser',
    dependencies => {
        fields       => 'report_fields',
        record_class => 'report_class',
        args_mangler => 'report_args_mangler',
    },
);

has reports_fh => (
    is       => 'ro',
    required => 1,
);

has reports => (
    is           => 'ro',
    isa          => ArrayRef[Report],
    lifecycle    => 'Singleton',
    dependencies => ['report_parser', 'reports_fh'],
    block        => fun ($s) {
        return [sort {
            $a->date <=> $b->date
        } $s->param('report_parser')->parse_fh(
            $s->param('reports_fh'),
        )];
    },
);

has student_reports => (
    is           => 'ro',
    isa          => HashRef[ArrayRef[Report]],
    lifecycle    => 'Singleton',
    dependencies => ['reports'],
    block        => fun ($s) {
        my %student_reports;

        push @{ $student_reports{ $_->student->nick } ||= [] }, $_
            for @{ $s->param('reports') };

        return \%student_reports;
    },
);

for my $attr (map { "reporting_period_${_}" } qw(start end)) {
    has $attr => (
        is           => 'ro',
        isa          => ISO8601DateTime,
        coerce       => 1,
        dependencies => ['config'],
        block        => fun ($s) {
            $s->param('config')->{$attr}
        },
    );
}

has reporting_period => (
    is           => 'ro',
    isa          => DateTimeSpan,
    dependencies => {
        map { ($_ => "reporting_period_${_}") } qw(start end),
    },
);

has reporting_interval => (
    is           => 'ro',
    isa          => Duration,
    coerce       => 1,
    dependencies => ['config'],
    block        => fun ($s) {
        $s->param('config')->{reporting_interval};
    },
);

has analysis_time => (
    is    => 'ro',
    isa   => DateTimeType,
    block => fun { DateTime->now(time_zone => 'local') },
);

has report_analyser => (
    is           => 'ro',
    isa          => ReportAnalyser,
    dependencies => ['reporting_period', 'reporting_interval', 'analysis_time'],
);

has student_report_analyses => (
    is           => 'ro',
    isa          => HashRef[ReportAnalysis],
    dependencies => ['report_analyser', 'student_reports', 'students'],
    block        => fun ($s, $c) {
        my $analyser = $s->param('report_analyser');
        my $reports = $s->param('student_reports');

        return {
            map {
                ($_->nick => $c->student_report_analysis($_))
            } values %{ $s->param('students') },
        };
    },
);

method student_report_analysis ($student) {
    $self->report_analyser->analyse(
        @{ $self->student_reports->{ $student->nick } },
    );
}

__PACKAGE__->meta->make_immutable;

1;
