#!/usr/bin/perl

# pragma
use utf8;
use strict;

# standard modules
use Encode;
use IO::Handle;
use FindBin;
use lib "$FindBin::Bin/lib";
use Getopt::Long;

# NLP modules
use PCPtoolkit;

# API

# common parameters
my $function;
my @params;
my $param={
	inputDir=>'./data',											# optional : default value='.' (e.g. '/the/dir/where/the/input/files/are/stored/')
	outputDir=>'./data',										# optional : default value=inputDir (e.g. '/the/dir/where/the/output/files/are/stored/')
	recursion=>0, 												# optional : default value=1 (all the subdirs are processed)
	processLinks=>0,											# optional : default value=0 (if 1, the symbolic links will be processed during recursion -> beware of the infinite loops !!!)
	filePattern=>qr/.*/,										# optional : default value=qr/.*/ (For instance qr/txt$/ will filter only *.txt files)
	fileEncoding=>'utf8',										# optional : default value='utf8'
	outputFileName=>[qr/(.*)/,'$1'],							# optional : defines the transformation of input filename in order to get the corresponding output filename. The default value depends on a specific action
	overwriteOutput=>0,											# if the output files already exists and overwriteOutput=0 then operation is aborted
	outputBackupExtension=>'no',								# ("no"|"bak"|"bakN") if the output files already exists and overwriteOutput=1, consider three cases :
																# "no" -> no backup
																# "bak"-> old version will be saved with .bak
																# "bakN"-> old versions wil be saved with bakN extension e.g. .bak0, .bak1, .bak2, etc.
	verbose=>0,													# optional : 1 to display on STDOUT execution trace
	printLog=>1,												# optional : 1 to print the execution trace in a log file 
	logFileName=>'PCPtoolkit.pl.log',						# the LOG file name - may contains timestamp variable e.g. 'PCPtoolkit.pl.$year-$mon-$mday.$hour-$min-$sec.log'
	windows=>0,
};

# Creating a pipeline, i.e. a set of parameters (cf. $param) for which a sequence of nlp processing will be done


GetOptions (
	'function=s' => \$function,
	'param=s{1,}' => \@params
);

# reading parameters on command line 
print "\nReading parameters on command line :\n" if @params;
foreach my $keyVal (@params) {
	if ($keyVal=~/^(.*?)=(.*)/) {
		my $parameter=$1;
		my $value=$2;
		$value=~s/\{\{(.*?)\}\}/\$$1/g;
		print "$parameter=$value\n";
		$param->{$parameter}=eval($value);
	}
}

if ($function) {
	print "\nrunning \$pipeline->".$function."()\n\n";
	my $pipeline=new PCPtoolkit($param);
	eval('$pipeline->'.$function."();");

} else {
	my $pipeline=new PCPtoolkit($param);

	my $pipelineFilename=shift @ARGV;


	open (IN,"<:utf8",$pipelineFilename) or die "Cannot open $pipelineFilename : check the file name and/or the permissions\n";
	my $line=<IN>;
	my $nextLine;
	chomp $line;
	
	# exit the loop when both $line and $nextLine are NULL
	while ($nextLine=<IN> or $line) {
		chomp $nextLine;
		$nextLine=~s/^(\s*)#.*/$1/; 	# ignoring comments
	
		# reading function call
		if ($line=~/^\s*->(die|exit|quit)\(.*\)/) {
			die "Pipeline died line $.\n";
		} elsif ($line=~/^->.*\(.*\)\s*;?\s*(#.*)?$/) {
			print "running \$pipeline$line\n";
			my $res=eval('$pipeline'.$line);
			if (! defined($res)) {
				print "======> ERROR : $@\n\n";
			}
		} elsif  ($line=~/^(.*?)=>?(.*)$/) {
			my $parameter=$1;
			my $val=$2;
			# reading parameter on multiple lines (while lines begins by tab)
			MULTILINE:while ($nextLine=~/^\t/) {
				$val.=$nextLine;
				$nextLine=<IN>;
				chomp $nextLine;
				$nextLine=~s/^\t#.*/\t/;
				
			}
			my $value=eval($val);
			if ($param->{verbose}) {
				print "$parameter = $value\n";
			}
			if (! defined($value)) {
				print "parameter $parameter cannot be read : there is an error in value=$val\n";
				die;
			}
			$pipeline->{$parameter}=$value;
		}
		$line=$nextLine;
	}
	close(IN);
	
}
