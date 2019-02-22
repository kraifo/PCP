#!/usr/bin/perl

# Function for corpus processing
# All function returns -1 when an error has occurred, and 0 when an operation is skipped

# TODO : 
# - attention débogage de la fonction convertParaCorp pas terminé (création d'un format parallèle txt2 à deux fichiers)
# - document the process() function (inputFileName, inputPattern, outputFileName, nameHash, recursion, result, etc.)
# - optimiser splitSent (trop long !)
# - pour lf_aligner, intégrer formats CES et txt en sortie, ajouter une option supprLFoutput
# - remplacer : runTreetagger runStanfordTagger par runTagger. Idem pour runAligner
# - posttraitement de treetagger trop longs : faire une lecture ligne par ligne du fichier

# line 1525 : use deps for conll relations


# List of fonctions

#~ renameFiles()
#~ extractStats()
#~ preTreetagger()
#~ runTreetagger()
#~ runXip()
#~ postXip()
#~ xip2conll()
#~ applyTemplate()
#~ convertEncoding()
#~ runExternalCommand()
#~ html2txt()
#~ mergeFiles()
#~ splitFiles()
#~ findAndReplace()
#~ splitSentences()
#~ tokenize()
#~ addParaTag()
#~ search()
#~ teiFormat()
#~ extractCoocTable()
#~ displayCollocations()
#~ anaText()
#~ convertParaCorp()
#~ mergeParaCorp()
#~ evalParaCorp()
#~ runAlineaLite()
#~ runYasa()
#~ runJam()
#~ runLFA()


package PCPtoolkit;  

# pragma

use utf8;
use strict;

# modules

use Encode;


use IO::Handle;
use FindBin;
my $scriptDir=decode_utf8($FindBin::Bin); # to use carefully : OS must recognize UTF8 for filenames

#~ $scriptDir=$FindBin::Bin;

use lib ("$scriptDir/","$scriptDir/DB_File","$scriptDir/XML","$scriptDir/Encode/Detect");
#~ use DB_File;
my $useDbFile=0;
use JSON;
use Entity2uni;
use Time::localtime;
use File::Basename qw(dirname basename fileparse);
use File::Path qw(make_path);
use re 'eval'; # look at line 714
use Data::Dumper;
use Crawler;
use Encode::Detect::Detector;
use MultiBleu;


binmode(STDOUT,":utf8");

#------------------------------------------------------------------------------------------------
use Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw( &renameFiles &setParam &next &runTreetagger &html2txt &mergeFiles &loadTagsets %data %callBacks &convertParaCorp &mergeParaCorp); 	
our $VERSION  = '3.2'; 


#------------------------------------------------------------------------------------------------
# global variables

my %searchResults;		# records the results of the corpus search function
our %data;				# hash of additionnal data used in templates and other function
our %collocList;
our %callBacks;			# hash of callBack functions that may used in replace function
#~ our $n;
my %entity2uni;
my $verbose=1;
my $defaultEncodingIfNotGuessed="cp1252";

# default parameters values
my $defaultParam={
	installDir=>"$scriptDir",
	inputDir=>"$scriptDir/data/input",						# e.g. '/the/dir/where/the/input/files/are/stored/'
	outputDir=>"$scriptDir/data/output",						# e.g. '/the/dir/where/the/output/files/are/stored/'
	logDir=>"$scriptDir/log",
	logFileName=>'PCPtoolkit.pl.log',						# the LOG file name - may contains timestamp variable e.g. 'PCPtoolkit.pl.$year-$mon-$mday.$hour-$min-$sec.log'
	appendLog=>1,												# if 1, the log file named PCPtoolkit.pl.log is open in append mode
	recursion=>1, 												# if 1, all the subdirs are processed
	processLinks=>0,											# if 1, the symbolic links will be processed during recursion -> beware of the infinite loops !!!
	filePattern=>qr/(.*)/,										# For instance qr/txt$/ will filter only *.txt files
	fileEncoding=>'utf8',										# 
	outputFileName=>[qr/(.*)/,'$1'],							# defines the transformation of input filename in order to get the corresponding output filename. The default value depends on a specific action
	overwriteInput=>0,											# if 1, when output filename is equal to input filename, input may be overwritten - if 0 the operation will be aborted
	overwriteOutput=>0,											# if the output files already exists and overwriteOutput=0 then operation is aborted
	outputBackupExtension=>'no',								# ("no"|"bak"|"bakN") if the output files already exists and overwriteOutput=1, consider three cases :
																# "no" -> no backup
																# "bak"-> old version will be saved with .bak
																# "bakN"-> old versions wil be saved with bakN extension e.g. .bak0, .bak1, .bak2, etc.
	verbose=>1,													# if 1, display execution trace on STDOUT 
	printLog=>1,												# if 1, print execution trace in a log file
	windows=>0,													# 1 for a windows install
	dicPath=>"$scriptDir/dic",
	grmPath=>"$scriptDir/grm",	
	tagsetName=>"tagsetTreetagger",								# tagset defaultPrefix
	sentMark=>"SENT",
	defaultTokRules=>[											# default tokenization rules
		{type=>'word',regex=>qr/[\w\-]+'?/},
		{type=>"ponct",regex=>qr/[.!?,;:"\(\)]/},
		{type=>"spc",regex=>qr/^(\s+)(.*)/},
		{type=>"char",regex=>qr/^(.)(.*)/}
	],
	sources=>[],
	language=>'fr',
};

my $renameFilesDefaultParam={
	confirm=>'no'
};

my $extractStatsDefaultParam={
	mode=>'append'
};

my $preTreetaggerDefaultParam={
};

my $treetaggerDefaultParam={
	treetaggerPath=>"$scriptDir/lib/treetagger",							# treetagger install path
	treetaggerOptions=>"-token -lemma -sgml -no-unknown -eos-tag \"<br/>\"",		# treetagger options
	treetaggerLanguage=>"french-utf8",							# treetagger options
	treetaggerAppName=>'tree-tagger',							# sometimes treetagger.exe
	tokenize=>1,
	treetaggerTokenizer=>'tokenize.perl',						# tokenizer must be installed in treetaggerPath/cmd
	treetaggerUTF8Tokenizer=>'utf8-tokenize.perl',
	treetaggerTokenizerOption=>'-f',
	supprSpcTag=>1,
	sentMark=>"SENT",
	addSentTag=>1,
	normalize=>1,
	normalizePatterns=>[[qr/[’`´′‛ʻʼ]/,"'"]],					# normalization patterns
	ext=>"ttg",
};

my $runStanfordPosTaggerDefaultParam={
	stanfordPath=>"$scriptDir/lib/stanford",
	
};

my $runXipDefaultParam={
	xipPath=>"$scriptDir/lib/xip-13.00-25",
	xipAppName=>"bin/linux/xip_kif",
	#~ xipAppName=>"bin/linux64/xip",
	xipOptions=>"-f -testutf8 -outpututf8",
	xipLanguage=>"fr", # ou "en" ou "en2"
	xmlElement=>"p", # l'élement xml à traiter
	grammars=>{
		"fr"=>"$scriptDir/lib/xip-13.00-25/grammar/french/basic/french_entity.grm",
		"en"=>"$scriptDir/lib/xip-13.00-25/grammar/english/norm/gram_norm_entit.grm",
		"en2"=>"$scriptDir/lib/xip-13.00-25/grammar2/ENGLISH/GRMFILES/GRAM_GEN/gram_gen_entit.grm",
	}
};

my $postXipDefaultParam={
	
};
my $xip2conllDefaultParam={
	sentTag=>"s",
	tokTag=>"t",
	depTag=>"d",
	depGroupTag=>"dc",
	numAttr=>"num",
	lemmaAttr=>"l",
	catAttr=>"c",
	feaAttr=>"f",
	relAttr=>"rel",
	headAttr=>"h",
	depAttr=>"d",

};



my $applyTemplateDefaultParam={
	template=>"$scriptDir/grm/tei.tpl",
};

my $convertEncodingDefaultParam={
	fromEncoding=>'iso-8859-1',
	toEncoding=>'utf8',
};

my $runExternalCommandDefaultParam ={
	saveOutputStream=>0
};


my $html2txtDefaultParam={
	deleteTags=>["script","style","head","nav"],
	blockTags=>["p","div","h1","h2","h3","li","br","hr","td","section","header","footer"]
};

my $mergeFilesDefaultParam={
	fileSeparator=>'\n<file name=\\"$fileName\\" />\n',
};


my $splitFilesDefaultParam={
	maxSize=>1000,
	splitAtEol=>1,
	outputFileName=>[qr/(.*)[.](\w+)$/,'$1.$n.$2']
};


my $findAndReplaceDefaultParam={
};

my $splitSentencesDefaultParam={
	language=>'fr',
	delimiter1=>".!?",
	delimiter2=>":;",
};

my $tokenizeDefaultParam={
	language=>'fr',
	tokSeparator=>"\n",
	printType=>0,
	typeSeparator=>"\t",
	newLineTag=>"br",
	spcTag=>"spc"
};

my $addParaTagDefaultParam={
	escapeMeta2Entities=>1,
	xmlTag=>'',
};

my $searchDefaultParam={
	grmPath=>"$scriptDir/grm",
	language=>'fr',
	outputConcord=>1,
	outputStat=>1,
	outputConcordFormat=>'kwik',# 'kwik' | 'XML'
	span=>40,					# number | 'sent'
	spanUnit=>'char',			#
	queryFile=>'',				# a file with one query per line
	countBy=>'form', 			# 'query' | 'lemma' | 'form' | 'cat'
	groupByFile=>1,				# if 1, all the results are grouped independtly for each files. If 0, all the data are merged
	sortBy=>['F','expr'],		#  'F' | 'alpha' | 'ahpla' | 'rightContext' | 'leftContext' | 'text'
	tokenSeparator=>"",			# put a space if the tokenizer does not leave spaces
	privateTagset=>{},			# a hash including specific tags used in the query
};

my $teiFormatDefaultParam={
	addHeader=>1,
	mergeInOneFile=>1,
	dataFilePattern=>qr/(.*)/,'$1.meta',

};

my $extractCoocTableDefaultParam= {
	coocTable=>"lemma.span4.dat",
	countBy=>'lemma_cat',
	useDbm=>1,
	coocSpan=>4,
	repeatedSegmentsMaxLength=>8,
	useSimplifiedTagset=>1,
	entrySep=>"_",
	c1Pattern=>[qr/.*/],
	c2Pattern=>[qr/.*/],
	relPattern=>[qr/.*/],
	minCoocFreq=>0,
	catPattern=>[qr/(.*?)(:.*)?$/,'$1'],
	language=>"fr",
	features2record=>{"VER"=>qr/simp|futu|impf|pper|infi|pres|subp|subi/}
};

my $displayCollocationsDefaultParam= {
	c1Pattern=>[qr/.*/],
	c2Pattern=>[qr/.*/],
	filterBy=>['log-like>10.83'],
	orderBy=>['log-like','c1','c2'],
	displayColumns=>['c1','c2','f1','f2','f12','log-like'],
	entrySep=>"_",
};

my $anaTextDefaultParam= {
	entrySep=>"__",
	vocIncreaseStep=>100,
};

my $convertParaCorpDefaultParam={
	idSentPrefix=>"s",
	supprPeriod=>1,
	languagePattern=>qr/\.([^.]*).\w{2,4}$/,			# for filenames like NAME.LANG.EXT
#"	commonNamePattern=>qr/(.*)\.[^.]+\.\w{2,4}$/		# for filenames like NAME.LANG.EXT
};

my $mergeParaCorpDefaultParam={
	idSentPrefix=>"s",
	supprPeriod=>1,
	languagePattern=>qr/\.([^.]*).\w{2,4}$/,			# for filenames like NAME.LANG.EXT
#	commonNamePattern=>qr/(.*)\.[^.]+\.\w{2,4}$/		# for filenames like NAME.LANG.EXT
};

my $evalParaCorpDefaultParam={
	idSentPrefix=>"s",
	supprPeriod=>1,
	languagePattern=>qr/\.([^.]*).\w{2,4}$/,			# for filenames like NAME.LANG.EXT
#	commonNamePattern=>qr/(.*)\.[^.]+\.\w{2,4}$/		# for filenames like NAME.LANG.EXT
};

my $computeBleuDefaultParam={
	refNumber=>2,
};

my $runAlineaLiteDefaultParam={
	idSentPrefix=>"s",
	alineaDir=>"$scriptDir/lib/alineaLite",
	outputFormat=>"txt",
	alignFileName=>'$commonName.$l1-$l2.$ext',
};

my $runYasaDefaultParam={
	yasaDir=>"./lib",
	idSentPrefix=>"",
	printScore=>1,
	radiusAroundAnchor=>30,
	splitSent=>1,
	alignFileName=>'$commonName.$l1-$l2.$ext',
	outputFormats=>['tmx','ces'],
};
my $runJamDefaultParam={
	jamDir=>"$scriptDir/lib",
	idSentPrefix=>"s",
	options=>"--finalCompletion --printMergedAlignment --printPairwiseAlignment",
	splitSent=>1	
};

my $runLFADefaultParam={
	LFADir=>"$scriptDir/lib/LF\\ Aligner",
	splitSent=>0,
};

#------------------------------------------------------------------------------------------------
# global variables

my $nbFileProcessed=0;

#------------------------------------------------------------------------------------------------

# public methods

# constructor of the main object : the pipeline for which all the processes will be done
sub new {
	my $class=shift;
	my $param=shift;
	my $this={};
	bless ($this,$class);
	$this->setParam($defaultParam);
	$this->setParam($param,{overwriteParam=>1});
	
	my $year=localtime->year();
	my $min=localtime->min();
	my $hour=localtime->hour();
	my $sec=localtime->sec();
	my $mon=localtime->mon();
	my $mday=localtime->mday();
	
	# open the log file if necessary
	if ($this->{printLog}) {
		if (! -e $this->{logDir}) {
			$this->printTrace("Creating directory $this->{logDir}\n");
			my $res=make_path($this->{logDir});
			if (! $res) {
				$this->printTrace("Unable to create $this->{logDir}\n",{warn=>1});
			}
		}
		
		my $logFile=$this->{logDir}."/".$this->{logFileName};

		if ($this->{appendLog}) {
			open (LOG,">>:encoding(utf8)",$logFile);
		} else {
			open (LOG,">:encoding(utf8)",$logFile);
		}
		$this->printTrace("\n\n\n########### Starting pipeline on $mday/$mon/".(1900+$year)." - $hour:$min:$sec\n\n");

	}
	
	return $this;
}

#*************************************************************************** setParam($param,$options)
# set param values according to the key->value pairs of the hash
# if $options->{overwriteParam} is set to 0, new param will not overwrite olders
sub setParam {
	my $this=shift;
	my $hash=shift;
	my $options={overwriteParam=>0};
	if (@_) {
		$options=shift;
	}
	
	
	foreach my $key (keys %{$hash}) {
		if (! exists($this->{$key}) || $options->{overwriteParam}) {
			$this->{$key}=$hash->{$key};
		}
	}
}

#*************************************************************************** next()
# inputDir takes the value of the previous outputDir, and $filePattern is reseted

sub next {
	my $this=shift;
	$this->{inputDir}=$this->{outputDir};
	$this->{filePattern}=qr/.*/;
}

#*************************************************************************** renameFiles($options)
sub renameFiles {
	my $this=shift;
	my $options=shift;

	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($renameFilesDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	
	$this->printTrace("\n########### Executing function renameFiles()\n");

	$this->{callback}= sub {
		my $fileName=shift;
		
		my $res=1;
		# version incluant le chemin dans le schéma de remplacement
		#~ my $newFileName=$this->{outputDir}."/".basename($fileName);
		#~ my $replace = '"'.$this->{outputFileName}->[1].'"';
		#~ my $res=1;
		#~ $newFileName=~s/$this->{outputFileName}->[0]/$replace/ee; # the trick is to evaluate potential $1, $2, etc.
		my $outputFileName=$this->handleNewFileName($fileName);
		if ($outputFileName eq "0" or $outputFileName eq "-1") {
			return $outputFileName ;
		}		
		
		$this->printTrace("Renaming $fileName to $outputFileName\n");

		if ($options->{confirm} eq 'yes') {
			$res=$res && rename ($fileName,$outputFileName);
		}
		return $res;
	};
	
	my $res=$this->process('Renaming Files');
	# restoring the previous settings
	$this->restoreParam();
	return $res;
}

#*************************************************************************** extractStats()
sub extractStats {
	my $this=shift;
	my $options=shift;

	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($extractStatsDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});

	my $res=0;
	$this->printTrace("\n########### Executing function stats()\n");

	my $newFileName=$this->{outputDir}."/".$this->{outputFileName};
	# creating file directory
	if ($this->createDir($newFileName)==-1) {
		return -1;
	}
	$newFileName=$this->ifFileExistBackupOrAbort($newFileName);
	
	if ($newFileName eq "0") {
		$this->printTrace($this->{outputDir}."/".$this->{outputFileName}." already exists and overwriteOutput=0 : operation is aborted\n",{warn=>1});
		return 0;
	}

	my $mode=">";
	if ($this->{mode} eq "append") {
		$mode=">>";
	}

	if (open(OUT,$mode,$newFileName)) {
		my $totalFileNum=0;
		my $totalLineNum=0;
		my $totalCharNum=0;
		my $totalTokNum=0;
		
		
		# setting callback function
		$this->{callback}= sub {
			my $fileName=shift;
			my $res=1;
			
			$this->printTrace("Reading $fileName\n");

			if (open(FILE,"<:encoding(".$this->{fileEncoding}.")",$fileName)) {
				$totalFileNum++;
				my $lineNum=0;
				my $charNum=0;
				my $tokNum=0;
				while (!eof(FILE)) {
					my $line=<FILE>;
					$line=~s/\x0D?\x0A?$//;
					$lineNum++;
					$charNum+=length($line);
					$tokNum+=split(/\b/,$line);
				}
				close(FILE);
				print OUT $fileName."\t$charNum chars\t$tokNum tokens\t$lineNum lines\n";
				$totalLineNum+=$lineNum;
				$totalCharNum+=$charNum;
				$totalTokNum+=$tokNum;
			} else {
				$this->printTrace("Unable to open $fileName\n",{warn=>1});
				$res=0;
			}
			return $res;
		};
		
		# run !
		$res = $this->process('Computing statistics');
		print OUT "Total file number\t$totalFileNum\n";
		print OUT "Total line number\t$totalLineNum\n";
		print OUT "Total token number\t$totalTokNum\n";
		print OUT "Total char number\t$totalCharNum\n";
		close(OUT);
	}
	
	$this->restoreParam();
	return $res;
}

#*************************************************************************** runTreetagger()
# Parameters :
# - treetaggerPath : string - treetagger install path - must be set for any installation 
# - treetaggerOptions : string - treetagger options - default="-token -lemma -sgml -no-unknown"
# - treetaggerLanguage : string - treetagger language - default="french-utf8" (the parameters file must be treetaggerPath/lib/treetaggerLanguage.par)
# - treetaggerAppName : string - treetagger binary executable - default='tree-tagger' (for windows 'treetagger.exe')
# - tokenize : boolean - if false, no tokenization is done
# - treetaggerTokenizer : string - the name of the tokenizer, wich must be installed in treetaggerPath/cmd - default='tokenize.perl'
# - treetaggerUTF8Tokenizer : string - the name of the tokenizer for utf8 files, wich must be installed in treetaggerPath/cmd - default='utf8-tokenize.perl'
# - windows : boolean - 1 for Windows OS
# - addSentTag : boolean - 1 to add <s> </s> tags
# - supprSpcTag : boolean - 1 to remove <spc> and add it to forms (first column)

sub runTreetagger {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($treetaggerDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});


	$this->printTrace("\n########### Executing function runTreetagger()\n");
	
	if (! -d $this->{treetaggerPath}) {
		$this->printTrace("the treetagger directory does not exist : $this->{treetaggerPath}. Please copy your complete distribution of treetagger in this directory, or change the 'treetaggerPath' setting.\n",{warn=>1});
		return 0;
	}
	if (! -f $this->{treetaggerPath}."/bin/".$this->{treetaggerAppName}) {
		$this->printTrace("the treetagger binary does not exist : ".$this->{treetaggerPath}."/bin/".$this->{treetaggerAppName}." Please verify your installation of treetagger or change the 'treetaggerAppName' setting.\n",{warn=>1});
		return 0;
	}
	
	
	$this->{callback}= sub {
		my $fileName=shift;
		my $inputDir=dirname($fileName);
		my $res=1;

		my $outputFileName=$this->handleNewFileName($fileName); # computes the new name and directory, creates the directory and backups previous versions if necessary

		if ($outputFileName eq "0" or $outputFileName eq "-1") {
			return $outputFileName ;
		}
		
		# preprocessing
		if ($this->{normalize}) {
			my $normalizePatterns=$this->{normalizePatterns};
			if (! $this->{windows}) {
				push(@{$normalizePatterns},[qr/\x0D\x0A/,"\n"]);
			}
				
			$this->findAndReplace({
				inputFileName=>$fileName,
				outputDir=>$inputDir,
				outputFileName=>[qr/$/,'.tmp'],
				searchReplacePatterns=>$this->{normalizePatterns},
			});
			$fileName=$fileName.'.tmp';
		}

		# running treetagger
		my $treetaggerPath=$this->{treetaggerPath};
		my $treetaggerLanguage=$this->{treetaggerLanguage};
		my $treetaggerOptions=$this->{treetaggerOptions};
		my $treetaggerAppName=$this->{treetaggerAppName};
		my $parFile="$treetaggerLanguage.par";
		
		$this->printTrace("Processing treetagger on $fileName - output=$outputFileName\n");
		my $tokenizer="$treetaggerPath/cmd/".$this->{treetaggerTokenizer};
		if ($this->{fileEncoding} eq 'utf8') {
			$tokenizer="$treetaggerPath/cmd/".$this->{treetaggerUTF8Tokenizer};
		}
		if (exists($this->{tokenizer})) {
			$tokenizer=$this->{tokenizer};
		}
		
		my $command;
		

		
		if ($this->{tokenize}) {
			$command="perl $tokenizer $this->{treetaggerTokenizerOption} -a $treetaggerPath/lib/$treetaggerLanguage-abbreviations \"$fileName\" | $treetaggerPath/bin/$treetaggerAppName $treetaggerPath/lib/$parFile $treetaggerOptions > \"$outputFileName\"";
		} else {
			$command="$treetaggerPath/bin/$treetaggerAppName $treetaggerPath/lib/$parFile \"$fileName\" $treetaggerOptions > \"$outputFileName\"";
		}
		if ($this->{windows}) {
			$command=~s/\//\\/g;
		}
		$this->printTrace("Command : $command \n");
		
		system($command);
		if ($? == -1) {
			$this->printTrace("failed to execute: $!\n",{warn=>1});
			$res=0;
		} elsif ($? & 127) {
			$this->printTrace(sprintf("child died with signal %d, %s coredump\n",($? & 127), ($? & 128) ? 'with' : 'without'),{warn=>1});
			$res=0;
		} else {
			$this->printTrace(sprintf(sprintf "child exited with value %d\n", $? >> 8),{warn=>1});
	
			if ($this->{supprSpcTag}) {
				$this->printTrace("\n########### Executing post-processing on $outputFileName\n");
				$this->{supprSpcTag} && $this->printTrace("- <spctag> removal\n");
				$this->{addSentTag} && $this->printTrace("- adding sent tag\n");
	
				my $searchReplacePatterns=[[qr/([^\t]+)\t([^\t]+)\t(\S+)\n<spc value='(.*?)' \/>[^\n]*/,'$1$4\t$2\t$3'],[qr/<spc value='(.*?)' \/>\n/,'']];
							# temporary parameters allows to overwrite on input
				$this->findAndReplace({
					inputFileName=>$outputFileName,
					outputFileName=>[basename($outputFileName)],
					searchReplacePatterns=>$searchReplacePatterns,
					inputDir=>$this->{outputDir},
					overwriteInput=>1, overwriteOutput=>1}
				);
			}

			
			if ($this->{addSentTag}) {
				open(IN,$outputFileName);
				my $text=join("",<IN>);
				close(IN);
				$text=~s/(<p( [^>]*)?>\n?)/$1<<SENT>>/g; # adding <<SENT>> after <p>
				$text=~s/(<\/\s*p\s*>)/<<SENT>>$1/g; # adding <<SENT>> before </p>
				$text=~s/(\t$this->{sentMark}(\t\S+)\n)/$1<<SENT>>/g; # adding <<tag>> after end of sentence
				my @segs=split(/<<SENT>>/,$text); # split text in segments
				my $sId=1;
				@segs=map { my $res=$_; if ($_=~/(\t[^\t\n]+(\t\S+)\n)$/) { $res= '<s id="'.($sId++)."\">\n".$_."</s>\n"} ; $res } @segs;
				open(OUT,">",$outputFileName);
				print OUT join("",@segs);
				close(OUT);
			}
		}
		unlink($fileName);
		return $res;
	};
	
	my $res=$this->process('Running treetagger');
	# restoring the previous settings
	$this->restoreParam();
	return $res;
}

# normalization of quotes for treetagger
sub preTreetagger {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($preTreetaggerDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});

	
	$this->printTrace("\n########### Executing function preTreetagger()\n");
	
	$this->setParam( {
		searchReplacePatterns=>[[qr/[’`´′‛ʻʼ]/,"'"]]
	},{overwriteParam=>1});
	

	$this->findAndReplace();

	# restoring the previous settings
	$this->restoreParam();
}

# adding the space mark to the end of surface form
# if $this->{addSentTag}=1, add sentence tags <s id='sid'>...</s>
sub postTreetagger {
	my $this=shift;
	
	# adding optionnal temporary parameters
	$this->saveParam();
	
	if (@_) {
		my $options=shift;
		while (my ($key,$value)=each(%{$options})) {
			$this->{$key}=$value;
		}
	}
	
	$this->printTrace("\n########### Executing function postTreetagger()\n");
	
	my $searchReplacePatterns=[[qr/([^\t]+)\t([^\t]+)\t(\S+)\n<spc value='(.*?)' \/>[^\n]*/,'$1$4\t$2\t$3']];
	
	if ($this->{addSentTag}) {
		# the first pattern add the tags, the second delete </s> at the beginning and <s id=""> and the end
		#~ push(@{$searchReplacePatterns},[qr/(^|([^\t]+)\tSENT\t(\S+)\n|$)/,'$1</s>\n<s id=\"s".($_++)."\">\n'],[qr/^<\/s>\n|\n<s id="[^"]*">\n$/,'']);
		
		# add </s> behind SENT if no </p> following
		push(@{$searchReplacePatterns},[qr/(([^\t]+)\tSENT\t(\S+)\n(?!<\/p>))/,'$1</s>']); 
		# add </s> in front of </p>
		push(@{$searchReplacePatterns},[qr/(<\/p>)/,'</s>\n$1']);	
		# add <s> betwen (<p> or </s>) and new token
		push(@{$searchReplacePatterns},[qr/(<p[^>]+>|<\/s>)\s*([^\t\n]+\t[^\t\n]+\t\S+|<spc[^>]+>)/,'$1\n<s id=\"s".($_++)."\">\n$2']);
		# suppress 	first </s> and last <s>
		#~ push(@{$searchReplacePatterns},[qr/<\/s>$/,'']);
	}
	
	# saving the previous settings
	$this->saveParam();
	
	my $filePattern=$this->{outputFileName}[1];
	
	# the new input files are the treetagger output files
	$filePattern=~s/(\$\d+)/.*/g;
	
	$this->setParam( {
		filePattern=>$filePattern,
		searchReplacePatterns=>$searchReplacePatterns
	},{overwriteParam=>1});
	

	$this->findAndReplace();

	# restoring the previous settings
	$this->restoreParam();
}



#*************************************************************************** runStanfordPosTagger()
# running stanford Segmenter and PosTagger only for Arabic
# Parameters :
# - outputFormat : string - ttg for treetagger format

sub runStanfordPosTagger {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($runStanfordPosTaggerDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});


	$this->printTrace("\n########### Executing function runStanfordPosTagger()\n");
	
	$this->{callback}= sub {
		my $fileName=shift;
		my $inputDir=dirname($fileName);
		my $res=1;

		my $outputFileName=$this->handleNewFileName($fileName); # computes the new name and directory, creates the directory and backups previous versions if necessary

		if ($outputFileName eq "0" or $outputFileName eq "-1") {
			return $outputFileName ;
		}
		
		# running stanford Segmenter and PosTagger
		my $stanfordPath=$this->{stanfordPath};
		
		my $command;
		$command="java -cp $stanfordPath/seg.jar edu.stanford.nlp.international.arabic.process.ArabicSegmenter -loadClassifier $stanfordPath/models/arabic-segmenter-atbtrain.ser.gz -textFile $fileName > $fileName.seg";
		if ($this->{windows}) {
			$command=~s/\//\\/g;
		}
		system($command);
		$command="java -mx300m -cp '$stanfordPath/stanford-postagger.jar:' edu.stanford.nlp.tagger.maxent.MaxentTagger -model $stanfordPath/models/arabic-accurate.tagger  -textFile $fileName.seg > \"$outputFileName\"" ;
		if ($this->{windows}) {
			$command=~s/\//\\/g;
		}
		$this->printTrace("Command : $command \n");
		system($command);
		if ($? == -1) {
			$this->printTrace("failed to execute: $!\n",{warn=>1});
			$res=0;
		} elsif ($? & 127) {
			$this->printTrace(sprintf("child died with signal %d, %s coredump\n",($? & 127), ($? & 128) ? 'with' : 'without'),{warn=>1});
			$res=0;
		} else {
			$this->printTrace(sprintf(sprintf "child exited with value %d\n", $? >> 8),{warn=>1});
	
			if ($this->{outputFormat} eq "ttg") {
				$this->printTrace("\n########### Executing post-processing on $outputFileName : conversion to ttg\n");
				my $searchReplacePatterns=[[qr/([^\/ ]+)\/([^\/ ]+) /,'$1\t$2\t$1\n']];
				# temporary parameters allows to overwrite on input
				$this->findAndReplace({
					inputFileName=>$outputFileName,
					outputFileName=>[basename($outputFileName)],
					searchReplacePatterns=>$searchReplacePatterns,
					inputDir=>$this->{outputDir},
					overwriteInput=>1, overwriteOutput=>1}
				);
			}

		}
		unlink($fileName.".seg");
		return $res;
	};
	
	my $res=$this->process('Running Stanford Segmenter and POS Tagger');
	# restoring the previous settings
	$this->restoreParam();
	return $res;
}


#*************************************************************************** runXip()
# Running xip on a XML formatted input file
# The text to process MUST be included between <p>...</p> or <s> tags </s> tags
# Parameters :
# - xipPath : string - xip install path - must be set for any installation 
# - xipOptions : string - xip options - default="-f -testutf8 -outpututf8 "
# - xipLanguage : string - xip language - default="fr" 
# - grammar : hash - various grammar files for various language
# - xipAppName : string - xip binary executable - default='bin/linux/xip_kif'
# - windows : boolean - 1 for Windows OS
# - xmlElement : p or s : the element which content has to be processed

sub runXip {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($runXipDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	
	$this->printTrace("\n########### Executing function runXip()\n");
	

	
	$this->{callback}= sub {
		my $fileName=shift;
		my $res=1;

		my $outputFileName=$this->handleNewFileName($fileName); # computes the new name and directory, creates the directory and backups previous versions if necessary

		if ($outputFileName eq "0" or $outputFileName eq "-1") {
			return $outputFileName ;
		}

		# running XIP
		my $xipPath=$this->{xipPath};
		my $xipLanguage=$this->{xipLanguage};
		my $xipOptions=$this->{xipOptions};
		my $xipAppName=$this->{xipAppName};
		my $xmlElement=$this->{xmlElement};

		my $command;
		
		my $grmFile;
		if (exists($this->{grammars}{$xipLanguage})) {
			$grmFile=$this->{grammars}{$xipLanguage};
		} else {
			$this->printTrace("\nPar de grammaire pour la langue [$xipLanguage] !!!\n");
			return 0;
		}
		
		$command="$xipPath/$xipAppName $xipOptions -kif ".$this->{installDir}."/lib/parseXml.kif -kifargs \"$fileName\" \"$outputFileName\" \"$grmFile\" \"$xmlElement\"";
		
		if ($this->{windows}) {
			$command=~s/\//\\/g;
		}
		print "Exec command : $command\n";
		
		# date management for "en2" : to run in sudo
		my $year=localtime->year();
		my $min=localtime->min();
		my $hour=localtime->hour();
		my $mday=localtime->mday();
		my $mon=localtime->mon();
		$mon++;

		# for en2, licenceDate must be equal to "10", for fr=>"14"
		if (exists($this->{licenceDate})) {
			system("date ".twoDigits($mon,$mday,$hour,$min,$this->{licenceDate}));
		}
		
		# run !!!
		system($command);
		
		if (exists($this->{licenceDate})) {
			system("date ".twoDigits($mon,$mday,$hour,$min,$year));
		}
		
		if ($? == -1) {
			$this->printTrace("failed to execute: $!\n");
			$res=0;
		} elsif ($? & 127) {
			$this->printTrace(sprintf("child died with signal %d, %s coredump\n",($? & 127), ($? & 128) ? 'with' : 'without'));
			$res=0;
		} else {
			$this->printTrace(sprintf(sprintf "child exited with value %d\n", $? >> 8));
		}
		return $res;
	};
	
	my $res=$this->process('Running Xip');
	# restoring the previous settings
	$this->restoreParam();
	return $res;
}


sub twoDigits {
	my $res="";
	foreach my $num (@_) {
		if (length($num)==1) {
			$res.= "0".$num;
		} else {
			$res.=substr($num,length($num)-2,2);
		}
	}
	return $res;
}


#*************************************************************************** postXip()
#  
sub postXip {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($postXipDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});

	$this->printTrace("\n########### Executing function postXip()\n");

	$this->{callback}= sub {
		my $fileName=shift;
		my $res=1;

		my $outputFileName=$this->handleNewFileName($fileName); # computes the new name and directory, creates the directory and backups previous versions if necessary


		if ($outputFileName eq "0" or $outputFileName eq "-1") {
			return $outputFileName ;
		}

		# XML processing of the output by defining callBack functions
		my $startTagCallBack=sub { # lorsqu'il rencontre une balise d'ouverture
			my $elt = shift ; # variable contenant le nom de la balise
			my $simple = shift ; # contient "/" dans le cas d'un marqueur simple
			my $attr_val = shift ; # tableau associatif contenant attribut/valeur de la balise
			my $refTheText = shift;
			my $refData= shift;

			############### placer ici les tests concernant le traitement des balises ouvrantes

			if (! exists($refData->{output})) {
				$refData->{output}=1;
			}

			if ($elt ne 'Analyse' && $elt ne 's' && $refData->{output}) {
				my $attrString="";
				foreach my $attr (keys %{$attr_val}) {
					$attrString.=" $attr=\"$attr_val->{$attr}\"";
				}
				if ($attrString) {
					print OUT $$refTheText."<$elt $attrString$simple>";
				} else {
					print OUT $$refTheText."<$elt$simple>";
				}
				$$refTheText="";
			}

			if ($elt eq 'Analyse') {
				# attention, peut contenir plusieurs phrases
				$refData->{sentences}=$$refTheText;
				# print "Phrase : ".$$refTheText."\n";
			}

			if ($elt eq "p") {
				$refData->{output}=0;
			}
			###############

		};


		#*************************************************
		# Texte compris entre deux balises
		my $pcDataCallBack=sub {
			my $refTheText= shift;
			my $refData= shift;
		};

		#*************************************************
		# Appelé à chaque balise de fin
		my $endTagCallBack= sub {
			my $elt = shift(@_);
			my $refTheText= shift;
			my $refData= shift;

			############### placer ici les tests concernant le traitement des balises fermantes

			if ($elt eq "Analyse") {
				my $text=${$refTheText};
				
				my @sents=split(/\n\n/,${$refTheText});

				foreach my $sent (@sents) {
					my @toks;
					my @deps;
					my @ds=split(/\n/,$sent);

					foreach my $d (@ds) {
						# lignes de la forme : MOD_PRE(.*) : lecture des dépendances
						if ($d=~/^(\w+?)[(](.*?)[)]/) {
							# on ignore les relations vers des tokens fictifs :
							if ($1 ne "SREL") {
								my @dep=($1);
								# on découpe les tokens au niveau de ,&lt;
								my @ts=split(/,&lt;/,$2);
								foreach my $t (@ts) {
								# tokens de la forme : &lt;NOUN:rates^rate^+83+88+Noun+countable+Pl+NOUN:17&gt;
									if ($t=~/^(?:&lt;)??(\w+?):(.*?):(\d+)&gt;$/) {
										#~ my $c=$1;
										my $id=$3;
										#~ my ($w,$l,$f)=split(/\^/,$2);
										#~ $toks[$id]=[$id,$w,$l,$c,$f];
										push(@dep,$id);
										# variante
									} elsif	($t=~/^(?:&lt;)??(\w+?):(.*?):(\d+),(.*?):(\d+)&gt;$/) {
										#~ my $c=$1;
										#~ my $wlf1=$2;
										my $id1=$3;
										#~ my $wlf2=$4;
										#~ my $id2=$5;
										#~ my ($w1,$l1,$f1)=split(/\^/,$wlf1);
										#~ my ($w2,$l2,$f2)=split(/\^/,$wlf2);
										#~ $toks[$id1]=[$id,$w1,$l1,$c,$f1];
										#~ $toks[$id1]=[$id1,$w1.$w2,$l1.$l2,$c,$f1.$f2];
										push(@dep,$id1);
									} else {
										print "token $t illisible\n";
										die;
									}
								}
								push(@deps,\@dep);
							}

						} else {
							# lecture des tokens : traitement de la dernière ligne de la forme 0&gt;TOP(0:34){NP(0:0){NOUN{Regulation^regulation^+0+10+Noun+Sg+NOUN:0}},NP(1:4){QUANT{No^no^+11+13+Noun+Sg+NOUN:1},DIG(2:4){DIG{467^467^+14+17+Dig+Card+CARD:2},PUNCT{/^/^+17+18+Punct+Spec+Right+Left+PUNCT:3},DIG{67^67^+18+20+Dig+Card+ShortYear+CARD:4}}},PUNCT{/^/^+20+21+Punct+Spec+Right+Left+PUNCT:5},NP(6:6){NOUN{EEC^EEC^+21+24+Prop+Misc+Acron+NOUN:6}},PP(7:9){PREP{of^of^+25+27+Prep+PREP:7},NP(8:9){DET{the^the^+28+31+Det+Def+SP+DET:8},NOUN{Commission^Commission^+32+42+Prop+orgHead+Sg+NOUN:9}}},PP(10:13){PREP{of^of^+43+45+Prep+PREP:10},NP(11:13){NOUN(11:13){DIG{21^21^+46+48+Dig+Card+Day+ShortYear+CARD:11},NOUN;ADJ{August^August^+49+55+Prop+Masc+Sg+firstName+NOUN:12},DIG{1967^1967^+56+60+Dig+Card+Year+CARD:13}}}},GV(14:14){VERB{fixing^fix^+61+67+Verb+a_vcreation+s_sc_pon+s_sc_pwith+s_p_up+Trans+Prog+VPROG:14}},NP(15:17){DET{the^the^+68+71+Det+Def+SP+DET:15},NOUN{conversion^conversion^+72+82+Noun+s_sc_pfrom+s_sc_pto+Sg+NOUN:16},NOUN{rates^rate^+83+88+Noun+countable+Pl+NOUN:17}},PUNCT{,^,^+88+89+Punct+Comma+CM:18},NP(19:21){DET{the^the^+90+93+Det+Def+SP+DET:19},AP(20:20){ADJ{processing^process^+94+104+Adj+VProg+ADJING:20}},NOUN{costs^cost^+105+110+Noun+Pl+NOUN:21}},CONJ{and^and^+111+114+Conj+Coord+COORD:22},NP(23:24){DET{the^the^+115+118+Det+Def+SP+DET:23},NOUN{value^value^+119+124+Noun+Sg+NOUN:24}},PP(25:27){PREP{of^of^+125+127+Prep+PREP:25},NP(26:27){DET{the^the^+128+131+Det+Def+SP+DET:26},NOUN{by-products^by-product^+132+143+Noun+Pl+NOUN:27}}},PP(28:31){PREP{for^for^+144+147+Prep+PREP:28},NP(29:31){DET{the^the^+148+151+Det+Def+SP+DET:29},AP(30:30){ADJ{various^various^+152+159+Adj+ADJ:30}},NOUN{stages^stage^+160+166+Noun+countable+Pl+NOUN:31}}},PP(32:33){PREP{of^of^+167+169+Prep+PREP:32},NP(33:33){NOUN{rice^rice^+170+174+Noun+Sg+NOUN:33}}},GV(34:34){VERB{processing^process^+175+185+Verb+Trans+Prog+VPROG:34}}}
							# on ajoute les signes de ponctuations, manquant :
							while ($d=~/(\w+?)\{([^}]+?)\^([^}]+?)\^([^}]+?):(\d+)\}/g) {
								my ($id,$w,$l,$c,$f)=($5,$2,$3,$1,$4);
								$f=~s/\+/ /g;
								$f=~s/^\s+|\s+$//g;
								$toks[$id]=[$id,$w,$l,$c,$f];
								# print "Ajout de [$id,$w,$l,$c,$f]\n";
							}
						}
					}
					if (! exists($refData->{sId})) {
						$refData->{sId}=0;
					}
					$refData->{sId}++;
					($refData->{sId} % 1000 ==0 ) && $this->printTrace("Phrase ".$refData->{sId}."\n");
					print OUT "	<s id='s$refData->{sId}'>\n";
					print OUT "		<tc>\n";
					# initialement $rest contient la phrase complète (surface)
					my $rest=$refData->{sentences};
					foreach my $tok (@toks) {
						if (!defined($tok)) {
							next;
						}
						my ($id,$w,$l,$c,$f)=@{$tok};

						# traitement des espaces (attribut e="")
						my $e=" "; # par défaut on met un espace
						# on prend la première occurrence de la forme de surface dans $rest et on regarde les espaces qui suivent.
						if ($rest=~/\Q$w\E(\s*)(.*)/s) {
							$e=$1;
							# remplacement des retours chariots par \n
							$e=~s/\n/\\n/g;
							# on tronque le reste
							$rest=$2;
						}

						if (! exists($refData->{tId})) {
							$refData->{tId}=0;
						}
						$refData->{tId}++;
						print OUT "			<t id=\"t$refData->{tId}\" num=\"$id\" l=\"".toXml($l)."\" c=\"$c\" f=\"$f\" e=\"$e\">$w</t>\n";
					}
					$refData->{sentences}=$rest; # le reste correspond aux phrases suivantes
					print OUT "		</tc>\n";

					print OUT "		<dc>\n";
					foreach my $dep (sort {$a->[1] <=> $b->[1]} @deps) {
						my ($rel,$h,$d,$d2)=@{$dep};
						if (defined($d2)) {
							print OUT "			<d rel=\"$rel\" h=\"$h\" d=\"$d\" d2=\"$d2\" />\n";
						} elsif (defined($d)) {
							print OUT "			<d rel=\"$rel\" h=\"$h\" d=\"$d\" />\n";
						} elsif (defined($h)) {
							print OUT "			<d rel=\"$rel\" h=\"$h\" />\n";
						} else {
							print "Anomalie relation vide $rel\n";
						}
					}
					print OUT "		</dc>\n";
					print OUT "	</s>\n";
				}
				$$refTheText="";
			} elsif ($elt eq "s") {
				# on ne fait rien
			} elsif ($elt eq "p") {
				$refData->{output}=1;
				print OUT "</$elt>";
			} elsif ($refData->{output}) {
				print OUT $$refTheText;
				print OUT "</$elt>";
				$$refTheText="";
			}

		###############
		};

		open(OUT,">:encoding(".$this->{fileEncoding}.")",$outputFileName);

		$res=parseXMLFile($fileName,$this->{fileEncoding},$startTagCallBack,$endTagCallBack,$pcDataCallBack,{});
		# analyse le fichier contenant le document XML

		close(OUT);

		return $res;
	};

	my $res=$this->process('Running PostXip');
	# restoring the previous settings
	$this->restoreParam();
	return $res;
}

#*************************************************************************** xip2conll()
# Converting postXip format to conll
# Parameters :
# - sentTag : string - tag used to encode strings - default ="s"
# - tokTag : string - tag used to encode tokens - default ="t"
# - depTag : string - tag used to encode dependency - default ="d"
# - depGroupTag : string - tag used to encode dependency groups - default ="dc"
# - numAttr : string - default ="num"
# - lemmaAttr : string - default ="l"
# - catAttr : string - default ="c"
# - feaAttr : string - default ="f"
# - relAttr : string - default ="rel"
# - headAttr : string - default ="h"
# - depAttr : string - default ="d"
# - tags2keep : [string*] - list of tag to keep in the output e.g. 'p', 'text'
sub xip2conll {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($xip2conllDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});

	$this->printTrace("\n########### Executing function xip2conll()\n");

	$this->{callback}= sub {
		my $fileName=shift;
		my $res=1;

		my $outputFileName=$this->handleNewFileName($fileName); # computes the new name and directory, creates the directory and backups previous versions if necessary


		if ($outputFileName eq "0" or $outputFileName eq "-1") {
			return $outputFileName ;
		}

		# XML processing of the output by defining callBack functions
		my $startTagCallBack=sub { # lorsqu'il rencontre une balise d'ouverture
			my $elt = shift ; # variable contenant le nom de la balise
			my $simple = shift ; # contient "/" dans le cas d'un marqueur simple
			my $attr_val = shift ; # tableau associatif contenant attribut/valeur de la balise
			my $refTheText = shift;
			my $refData= shift;

			############### placer ici les tests concernant le traitement des balises ouvrantes

			if ($elt eq $this->{tokTag}) {

				my $num=$attr_val->{$this->{numAttr}};
				$refData->{hashRel}{$num}=[];
				my $l=$attr_val->{$this->{lemmaAttr}};
				my $c=$attr_val->{$this->{catAttr}};
				my $f=$attr_val->{$this->{feaAttr}};
				$refData->{currentTok}=[$num,$l,$c,$f];
			}
			
			if (inArray($elt,@{$this->{tags2keep}})) {
				my $attrStr='';
				while (my ($attr,$value)=each %{$attr_val}) {
					$attrStr.=" $attr=\"$value\"";
				}
				print OUT "#<$elt$attrStr>\n";	# tags are added as comments
			}
			
			if ($elt eq $this->{depTag}) {
				my $rel=$attr_val->{$this->{relAttr}};
				my $id1=$attr_val->{$this->{headAttr}};
				my $id2=$attr_val->{$this->{depAttr}};
				if (!exists($refData->{hashRel}{$id2})) {
					$refData->{hashRel}{$id2}=[];
				}
				push(@{$refData->{hashRel}{$id2}},$id1."-".$rel);	# attaching dep to head - multiple attachment is possible
			}

			###############

		};


		#*************************************************
		# Texte compris entre deux balises
		my $pcDataCallBack=sub {
			my $refTheText= shift;
			my $refData= shift;
		};

		#*************************************************
		# Appelé à chaque balise de fin
		my $endTagCallBack= sub {
			my $elt = shift(@_);
			my $refTheText= shift;
			my $refData= shift;

			############### placer ici les tests concernant le traitement des balises fermantes

			if ($elt eq $this->{tokTag}) {
				my $w=$$refTheText;
				push(@{$refData->{currentTok}},$w);
				push(@{$refData->{toks}},$refData->{currentTok});
			}
			
			if ($elt eq $this->{depGroupTag}) {
				foreach my $tok (@{$refData->{toks}}) {
					my ($num,$l,$c,$f,$w)=@{$tok};
					if (! @{$refData->{hashRel}{$num}}) {
						$refData->{hashRel}{$num}[0]='0-root'
					}
					my ($head,$rel)=split("-",$refData->{hashRel}{$num}[0]); # first head, first relation
					my $deps=join(" ",@{$refData->{hashRel}{$num}});	# enhanced dependency graph
					print OUT join("\t",map { my $s=$_;$s=~s/[\t\n]//g;$s } ($num,$w,$l,$c,"_",$f,$head,$rel,$deps))."\n";
				}
				# clearing the hashes
				$refData->{hashRel}={};
				$refData->{toks}=[];
			}
			if ($elt eq $this->{sentTag}) {
				print OUT "\n";
			}	
			if (inArray($elt,@{$this->{tags2keep}})) {
				print OUT "#</$elt>\n";
			}
			
		###############
		};

		open(OUT,">:encoding(".$this->{fileEncoding}.")",$outputFileName);

		$res=parseXMLFile($fileName,$this->{fileEncoding},$startTagCallBack,$endTagCallBack,$pcDataCallBack,{});
		# analyse le fichier contenant le document XML

		close(OUT);

		return $res;
	};

	my $res=$this->process('Running xip2conll');
	# restoring the previous settings
	$this->restoreParam();
	return $res;
}

#*************************************************************************** validateIndent()
#  
sub indentXMLFile {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($postXipDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});

	$this->printTrace("\n########### Executing function indentXML()\n");

	$this->{callback}= sub {
		my $fileName=shift;
		my $res=1;
		my $niveau=0;
		my $niveauMax=10;
		my $indentString="\t";
		my $noIndentTag=qr/^$/;
		my $result;

		my $outputFileName=$this->handleNewFileName($fileName); # computes the new name and directory, creates the directory and backups previous versions if necessary


		if ($outputFileName eq "0" or $outputFileName eq "-1") {
			return $outputFileName ;
		}

		# XML processing of the output by defining callBack functions
		my $startTagCallBack=sub { # lorsqu'il rencontre une balise d'ouverture
			my $elt = shift ; # variable contenant le nom de la balise
			my $simple = shift ; # contient "/" dans le cas d'un marqueur simple
			my $attr_val = shift ; # tableau associatif contenant attribut/valeur de la balise
			my $refTheText = shift;
			my $refData= shift;

			############### placer ici les tests concernant le traitement des balises ouvrantes

			my $attrs="";
			foreach my $attr (keys %{$attr_val}) {
				# syntaxe HTML avec ' ' 
				if ($attr_val->{$attr}=~/^'.*'$/) {
					$attrs.=$attr."=".$attr_val->{$attr}." ";
				} else {	
					$attrs.=$attr."=\"".$attr_val->{$attr}."\" ";
				}
			}
			my $indent=($indentString x $niveau);
			my $cr="\n";

			# pour les balises définies par $noIndentTag, on supprime toutes les indentations (y compris les descendants)
			if ($elt=~/^($noIndentTag)$/ && $niveauMax==-1) {
				# on fixe $niveauMax. 
				$niveauMax=$niveau;
				# seul le retour chariot est neutralisé (c'est la première balise $noIndentag rencontrée)
				$cr="";	
			#$niveauMax enregistre le niveau au delà duquel on n'a plus d'indentations, on supprime toutes les indentations (y compris les descendants)
			} elsif ($niveauMax >-1) {
				$indent="";
				$cr="";
			}
			
			my $spc=($attrs ne "")?" ":"";		
			print OUT $indent."<".$elt.$spc.$attrs.$simple.">$cr";
			
			
			if (!$simple) {
				$niveau++;
			}
			###############

		};


		#*************************************************
		# Texte compris entre deux balises
		my $pcDataCallBack=sub {
			my $refTheText= shift;
			my $refData= shift;
		};

		#*************************************************
		# Appelé à chaque balise de fin
		my $endTagCallBack= sub {
			my $elt = shift(@_);
			my $refTheText= shift;
			my $refData= shift;

			############### placer ici les tests concernant le traitement des balises fermantes

			#################" TODO : terminer !!!!

		###############
		};

		open(OUT,">:encoding(".$this->{fileEncoding}.")",$outputFileName);

		$res=parseXMLFile($fileName,$this->{fileEncoding},$startTagCallBack,$endTagCallBack,$pcDataCallBack,{});
		# analyse le fichier contenant le document XML

		close(OUT);

		return $res;
	};

	my $res=$this->process('Running IndentXML');
	# restoring the previous settings
	$this->restoreParam();
	return $res;
}

#*************************************************************************** applyTemplate()
# applying a template, typically to tag in TEI form
# parameters :

# - template : string - the template file
# - data : hash ref - data to fill in the template
# - dataFilePattern : [/pattern/,replace] - pattern to transform inputFileName in dataFileName, a file which contains additionnal data (typically a *.meta file)

sub applyTemplate {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($applyTemplateDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});

	my $tpl;
	
	$this->printTrace("\n########### Applying template $this->{template}\n");
	
	if (($this->{fileEncoding} ne "raw" && open(TPL,"<:encoding(".$this->{fileEncoding}.")",$this->{template})) or  open(TPL,"<:raw",$this->{template})) {
		$tpl=join("",<TPL>);
		close(TPL);
	} else {
		$this->printTrace("Unable to open template file '$this->{template}'\n",{warn=>1});
		return -1;
	}
	
	# replacing template "{{field}}" by string "$data{'field'}"
	$tpl=~s/[{][{](.*?)[}][}]/\$data{'$1'}/g;

	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		my $res=1;
		%data=();

		my $outputFileName=$this->handleNewFileName($fileName); # computes the new name and directory, creates the directory and backups previous versions if necessary

		if ($outputFileName eq "0" or $outputFileName eq "-1")  {
			return $outputFileName ;
		}
		$this->printTrace("Applying template to $fileName, into $outputFileName\n");

		if (open(FILE,"<:encoding(".$this->{fileEncoding}.")",$fileName)) {

			# copying $fileName content to %data
			$data{'content'}=join("",<FILE>);
			close(FILE);

			# copying $this->{data} to %data
			while (my ($k,$v)=each %{$this->{data}}) {
				$data{$k}=$v;
			}
			
			# copying DATAFILE additional data to %data
			if ($this->{dataFilePattern}) {
				my $replace = '"'.$this->{dataFilePattern}->[1].'"';
				my $dataFileName=$fileName;
				$dataFileName=~s/$this->{dataFilePattern}->[0]/$replace/ee;
				$this->printTrace("Reading $dataFileName to get additional data\n");
				
				if (open(DATAFILE,"<:encoding(".$this->{fileEncoding}.")",$dataFileName)) {
					while (! eof(DATAFILE)) {
						my $line=<DATAFILE>;
						$line=~s/[\x0D\x0A]*$//g; # chomp
						my ($key,$value)=split(/[\t=]/,$line);
						$data{$key}=$value;
					}
					close(DATAFILE);
				} else {
					$this->printTrace("Unable to read $dataFileName\n",{warn=>1});
				}
			}

			# interpolating $data{'field'} variables
			my $text=eval('qq ¤'.$tpl.'¤');

			if (open(OUT,">:encoding(".$this->{fileEncoding}.")",$outputFileName)) {
				print OUT $text;
				close(OUT);
			} else {
				$this->printTrace("Unable to write $outputFileName",{warn=>1});
				return -1;
			}
		} else {
			$this->printTrace("Unable to read $fileName",{warn=>1});
			return -1;
		}
		return 1;
	};
	
	# run !
	my $res = $this->process('Applying template');

	$this->restoreParam();
	return $res;
}


#*************************************************************************** convertEncoding()
# convert encoding

sub convertEncoding {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($convertEncodingDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});	
	
	$this->printTrace("\n########### Executing function convertEncoding()\n");
	
	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		my $res=1;
		
		my $outputFileName=$this->handleNewFileName($fileName); # computes the new name and directory, creates the directory and backups previous versions if necessary

		if ($outputFileName eq "0" or $outputFileName eq "-1")  {
			return $outputFileName ;
		}
		$this->printTrace("Converting $fileName ($this->{fromEncoding}) to $outputFileName ($this->{toEncoding})\n");

		if (open(FILE,"<:encoding(".$this->{fromEncoding}.")",$fileName)) {
			my $text=join("",<FILE>);
			close(FILE);
			
			
			if (open(OUT,">:encoding(".$this->{toEncoding}.")",$outputFileName)) {
				print OUT $text;
				close(OUT);
			} else {
				$this->printTrace("Unable to write $outputFileName",{warn=>1});
				return -1;
			}
		} else {
			$this->printTrace("Unable to read $fileName",{warn=>1});
			return -1;
		}
		return 1;
	};
	
	# run !
	my $res = $this->process('Encoding conversion');
	$this->restoreParam();
	return $res;
}

#*************************************************************************** runExternalCommand()
# Running an external Command
# parameters :
# - externalCommand : string - the full path to external command
# - externalCommandArguments : string - the command line arguments, including interpolated  variables $inputFileName and $outputFileName
# - externalCommandOptions : string - the command line options
# - windows : boolean - 1 for Windows OS

sub runExternalCommand {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($runExternalCommandDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});	
	
	$this->printTrace("\n########### Executing function runExternalCommand()\n");
	
	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		my $inputDir=dirname($fileName);
		my $res=1;

		my $outputFileName=$this->handleNewFileName($fileName); # computes the new name and directory, creates the directory and backups previous versions if necessary

		if ($outputFileName eq "0" or $outputFileName eq "-1")  {
			return $outputFileName ;
		}

		my $inputFileName=$fileName;
		my $outputDir=dirname($outputFileName);

		my $command=eval('"'.$this->{externalCommand}.'"')." ".$this->{externalCommandOptions};
		if ($this->{saveOutputStream}) {
			$command.=" > \"".$outputFileName."\"";
		}

		if ($this->{externalCommandArguments}) {
			# var that can be used in the arguments : inputDir, outputDir, inputFileName, outputFileName, $1, $2 (the subpatterns of inputFileName) 
			my $arg=$this->{externalCommandArguments};
			$arg=~s/\$(\d+)/$this->{nameHash}{$1}/ge; # $1, $2 etc. are replaced by $this->{nameHash}{1}, $this->{nameHash}{2}, the subpatterns of inputFileName
			
			$command=eval('"'.$this->{externalCommand}.'"')." ".eval('"'.$arg.'"')." ".$this->{externalCommandOptions};
		}
		
		if ($this->{windows}) {
			$command=~s/\//\\/g;
		}
		$this->printTrace("Running command :\n$command\n");

		system($command);
		return $res;
	};
	
	# run !
	my $res = $this->process('Running external command');
	$this->restoreParam();
	return $res;
}

sub runOnceExternalCommand {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($runExternalCommandDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});	
	
	$this->printTrace("\n########### Executing function runOnceExternalCommand()\n");
	
	my $outputFileName=$this->handleNewFileName(); # computes the new name and directory, creates the directory and backups previous versions if necessary

	if ($outputFileName eq "0" or $outputFileName eq "-1")  {
		return $outputFileName ;
	}

	my $command=eval('"'.$this->{externalCommand}.'"')." ".$this->{externalCommandOptions};
	
	if ($this->{externalCommandArguments}) {
		# var that can be used in the arguments : inputDir, outputDir, outputFileName 
		my $arg=$this->{externalCommandArguments};
		my $inputDir=$this->{inputDir};
		my $outputDir=$this->{outputDir};
		$command=eval('"'.$this->{externalCommand}.'"')." ".eval('"'.$arg.'"')." ".$this->{externalCommandOptions};
	}

	if ($this->{saveOutputStream}) {
		$command.=" > \"".$outputFileName."\"";
	}

	if ($this->{windows}) {
		$command=~s/\//\\/g;
	}
	$this->printTrace("Running command :\n$command\n");

	my $res=system($command);
	
	$this->restoreParam();
	return $res;
}


#*************************************************************************** html2txt($options)
# deleting tags and html formating
# options : deleteTags=>[list of tags for which inner HTML content is deleted], blockTags=>[list of tags that involve newline]

sub html2txt {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($html2txtDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});	

	$this->printTrace("\n########### Executing function html2txt()\n");

	
	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		my $res=1;
		
		my $outputFileName=$this->handleNewFileName($fileName); # computes the new name and directory, creates the directory and backups previous versions if necessary

		if ($outputFileName eq "0" or $outputFileName eq "-1")  {
			return $outputFileName ;
		}
		$this->printTrace("Converting $fileName to $outputFileName\n");

		if (open(FILE,"<:encoding(".$this->{fileEncoding}.")",$fileName)) {
			my $text=join("",<FILE>);
			my $newText=strHtml2txt($text,$this->{deleteTags},$this->{blockTags});
			close(FILE);
			
			if (open(OUT,">:encoding(".$this->{fileEncoding}.")",$outputFileName)) {
				print OUT $newText;
				close(OUT);
			} else {
				$this->printTrace("Cannot write $fileName",{warn=>1});
				return -1;
			}
		} else {
			$this->printTrace("Cannot read $fileName",{warn=>1});
			return -1;
		}
		return 1;
	};
	
	# run !
	my $res = $this->process('Converting HTML to TXT');
	$this->restoreParam();
	return $res;
}

#*************************************************************************** mergeFiles($option)
# merges all the processed file in one file
# Options : fileSeparator=>"string that separates the files"
 
sub mergeFiles {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($mergeFilesDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});	
		
	my $outputFileName=$this->handleNewFileName($this->{inputDir}."/merged");

	if ($outputFileName eq "0" or $outputFileName eq "-1")  {
		return $outputFileName ;
	}
	
	if (open(OUTPUT,">:encoding(".$this->{fileEncoding}.")",$outputFileName)) {
		
		$this->printTrace("Writing merged file $outputFileName\n");

		# setting callback function
		$this->{callback}= sub {
			my $fileName=shift;
			my $res=1;

			if (open(FILE,"<:encoding(".$this->{fileEncoding}.")",$fileName)) {
				my $text=join("",<FILE>);
				close(FILE);
				
				if (exists($this->{fileSeparator})) {
					print OUTPUT eval('"'.$this->{fileSeparator}.'"');
				}
				print OUTPUT $text;
			}
		};
		
	
		# run !
		my $res = $this->process('Merging Files');
		$this->restoreParam();
		close(OUTPUT);
		return $res;
	} else {
		$this->printTrace("Unable to write $outputFileName",{warn=>1});
	}
}

#*************************************************************************** splitFiles($option)
# split all the processed file in files with a size that not exceeds $maxSize 

# Parameters : 
# - maxSize : integer - the max size in char
# - splitAtEol : boolean - if 1, split at the last eol()
# - filePattern : [pattern,replace] - as usual, but $n represents the file number, e.g. [/(.*)[.](\w+)$/],'$1.$n.$2']
 
sub splitFiles {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($splitFilesDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	
	$this->printTrace("\n########### Executing function splitFiles()\n");

	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		my $res=1;
		

		my $buffer='';
		if (open(FILE,"<:encoding(".$this->{fileEncoding}.")",$fileName)) {
			$this->printTrace("Splitting $fileName\n");
			my $n=1;
			while (! eof(FILE)) {
				
				my $outputFileName=$this->handleNewFileName($fileName,$n); # computes the new name and directory, creates the directory and backups previous versions if necessary

				if ($outputFileName eq "0" or $outputFileName eq "-1")  {
					return $outputFileName ;
				}
				while (length($buffer)<$this->{maxSize} && ! eof(FILE)) {
					$buffer.=<FILE>;
				}
				my $text=substr($buffer,0,$this->{maxSize});

				# cutting $text at last eol
				if ($this->{splitAtEol}) {
					if ($text=~/[\n\r][^\n\r]/) {
						$text=~s/[^\n\r]+$//;
					}
				}
				# $buffer will contain the rest
				$buffer=substr($buffer,length($text));

				$this->printTrace("Writing $fileName to $outputFileName\n");
				if (open(OUTPUT,">:encoding(".$this->{fileEncoding}.")",$outputFileName)) {
					print OUTPUT $text;
					close(OUTPUT);
				} else {
					$this->printTrace("Unable to write $outputFileName\n",{warn=>1});
				}
				$n++;
			}
			close(FILE);
		} else {
			$this->printTrace("Cannot read $fileName",{warn=>1});
			return -1;
		}
		return 1;
	};
	
	# run !
	my $res = $this->process('Splitting files');
	$this->restoreParam();
	return $res;
}

#*************************************************************************** findReplace ()
# search and replace patterns

sub findAndReplace {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($findAndReplaceDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	
	$this->printTrace("\n########### Executing function findAndReplace()\n");

	if (exists($this->{patternFile}) && open(PATTERNS,"<:encoding(utf8)",$this->{patternFile})) {
		$this->printTrace("Reading search patterns and replace strings\n");
		while (! eof(PATTERNS)) {
			my $line=<PATTERNS>;
			$line=~s/\x0D?\x0A?$//; # chomp
			my ($search,$replace)=split(/\t/,$line);
			push (@{$this->{searchReplacePatterns}},[qr/$search/,$replace]);
		}
	}

	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;

		my $outputFileName=$this->handleNewFileName($fileName); # computes the new name and directory, creates the directory and backups previous versions if necessary
		
		#~ print $this->{filePattern}." : ". $this->{outputFileName}[0]." !!! ".$fileName."   -------> $outputFileName\n";


		if ($outputFileName eq "0" or $outputFileName eq "-1")  {
			return $outputFileName ;
		}
		$this->printTrace("Writing to $outputFileName ($fileName)\n");

		if (open(FILE,"<:encoding(".$this->{fileEncoding}.")",$fileName)) {
			my $text=join("",<FILE>);
			close(FILE);
			
			$_=0;
			foreach my $searchReplacePatterns (@{$this->{searchReplacePatterns}}) {
				#~ print "search\t$searchReplacePatterns->[0]\n";
				#~ print "replace\t\"$searchReplacePatterns->[1]\"\n";
				$text=~s/$searchReplacePatterns->[0]/'"'.$searchReplacePatterns->[1].'"'/eesg;
			}
			
			if (open(OUT,">:encoding(".$this->{fileEncoding}.")",$outputFileName)) {
				print OUT $text;
				close(OUT);
			} else {
				$this->printTrace("Unable to write $outputFileName",{warn=>1});
				return -1;
			}
		} else {
			$this->printTrace("Unable to read $fileName",{warn=>1});
			return -1;
		}
		return 1;
	};
		
	
	# run !
	my $res = $this->process('Find and replace REGEX');
	$this->restoreParam();
	close(OUTPUT);	
	return $res;
}


#*************************************************************************** tokenize ()
# sentence segmentation
# return one sentence per line
# Parameters : 
# - delimiter1 : string - default ".?!" must be followed by space
# - delimiter2 : string - default ":;"
# - language : to select an abbrev.ll.txt dictionary

sub splitSentences {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($splitSentencesDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	
	$this->printTrace("\n########### Executing function splitSentences()\n");

	# loading the abbreviation dic
	$this->loadAbbrevDic($this->{language});

	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		my $lang=$this->{language};

		my $outputFileName=$this->handleNewFileName($fileName); # computes the new name and directory, creates the directory and backups previous versions if necessary

		if ($outputFileName eq "0" or $outputFileName eq "-1")  {
			return $outputFileName ;
		}

		if (open(FILE,"<:encoding(".$this->{fileEncoding}.")",$fileName)) {
			$this->printTrace("Reading from $fileName ($this->{fileEncoding})\n");
			if (open(OUTPUT,">:encoding(".$this->{fileEncoding}.")",$outputFileName)) {
				$this->printTrace("Writing to $outputFileName ($this->{fileEncoding})\n");
				while (! eof(FILE)) {
					my $line=<FILE>;
					# chomp
					$line=~s/[\r\n]+$//g;
					# empty lines are ignored
					if ($line !~/^\s*$/) {
						print OUTPUT $this->stringSplitSent($line);
					}
				}
				close (OUTPUT);
			} else {
				$this->printTrace("Unable to write $outputFileName",{warn=>1});
				return -1;
			}
			close (FILE);
		} else {
			$this->printTrace("Unable to read $fileName",{warn=>1});
			return -1;
		}
		return 1;
	};
		
	# run !
	my $res = $this->process('Sentence segmentation');
	$this->restoreParam();
	return $res;
}

sub stringSplitSent {
	my $this=shift;
	my $str=shift;
	
	my @sents;
	
	my $abbrev=$this->{abbrevDic};
	my $dot1=$this->{delimiter1};
	my $dot2=$this->{delimiter2};
	# traitement des exceptions : on neutralise le point par une marque <dot>
	$str=~s/(\s)($abbrev)\./$1$2<dot>/g;	# abréviation (précédée d'un espace)
	$str=~s/([\s\-][A-Z]h?)\./$1<dot>/g;	# initiale de prénom (précédé d'un espace ou d'un tiret
	$str=~s/([0-9]+)\./$1<dot>/g;			# nombre suivi d'un point

	
	my $split=1;
	while ($split) {
		my ($head,$rest);
		if ($str=~/^([^$dot2]+?[$dot1][»")]?)(\s+.*)$/) { 
		# cas général point esp
		# Ne pas oublier le ^ initial, car le +? n'étant pas 'gourmand' il faut forcer le motif 
		# à commencer au début de la phrase
		# Par ailleurs l'expr. commence par [^$points2]+? plutôt que .+? 
		# car s'il y a un point double dans la phrase, on segmente avant le point (règle suivante)
			$head=$1;
			$rest=$2;
		} elsif ($str=~/^(.+?[$dot2])(.*)$/) {# points doubles
			$head=$1;
			$rest=$2;
		} else {
			$head=$str;
			$rest="";
			$split=0;
		}
		$head=~s/<dot>/./g; # rétablissement des points
		if ($head) {
			push(@sents,$head);
		}
		$str=$rest;
	}
	return join("\n",@sents)."\n";
}


#*************************************************************************** tokenize ()
# text tokenization
# Parameters : 
# - spcTag : boolean - if 1, add <spc> tag to protect spaces
# - newLineTag : boolean - if 1, add <br/> for new lines
# - tokSeparator : string - default value="\n" - each token will be separated by it in the output
# - printType : boolean - if 1 add typeSeparator.type to the token


sub tokenize {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($tokenizeDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	
	$this->printTrace("\n########### Executing function tokenize()\n");

	# loading the tokenisation rules and dics
	$this->loadTokGrammar($this->{language});

	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		my $lang=$this->{language};

		my $outputFileName=$this->handleNewFileName($fileName); # computes the new name and directory, creates the directory and backups previous versions if necessary

		if ($outputFileName eq "0" or $outputFileName eq "-1")  {
			return $outputFileName ;
		}

		if (open(FILE,"<:encoding(".$this->{fileEncoding}.")",$fileName)) {
			$this->printTrace("Reading from $fileName\n");
			if (open(OUTPUT,">:encoding(".$this->{fileEncoding}.")",$outputFileName)) {
				$this->printTrace("Writing to $outputFileName\n");
				while (! eof(FILE)) {
					my $line=<FILE>;
					# chomp
					$line=~s/[\r\n]+$//g;
					print OUTPUT $this->stringTokenizer($line,$lang);
					
					# dernière ligne correspondant au retour chariot
					if ($this->{newLineTag}) {
						print OUTPUT "<".$this->{newLineTag}."/>";
						print OUTPUT $this->{tokSeparator};
					} 
				}
				close (OUTPUT);
			} else {
				$this->printTrace("Unable to write $outputFileName",{warn=>1});
				return -1;
			}
			close (FILE);
		} else {
			$this->printTrace("Unable to read $fileName",{warn=>1});
			return -1;
		}
		return 1;
	};
		
	# run !
	my $res = $this->process('Tokenization');
	$this->restoreParam();
	return $res;
}

# parameters
# - alreadyTokenized : boolean - if 1, keep the input unchanged

# tokenize a simple string using the appropriate grammar
sub stringTokenizer {
	my $this=shift;
	my $string=shift;
	my $lang=shift;
	my $result="";
	
	# some texts are already tokenized
	if ($this->{alreadyTokenized}) {
		return $string;
	}

	while ($string ne "") {
		my $found=0;
		RULE_LOOP:foreach my $rule (@{$this->{tokenizationGrm}{$lang}}) {
			my $regex;
			my $caseSensitive=1;
			if (exists($rule->{dicName})) {
				# attention, pour les composés, pas de sensibilité à la casse -> à revoir
				if ($rule->{dicName} eq "compounds") {
					$caseSensitive=0;
				}
				$regex=$this->{tokenizationDic}{$lang}->{$rule->{dicName}};
			} elsif (exists($rule->{regex})) {
				$regex=$rule->{regex};
			}

			if ($string=~$regex || ($string=~/$regex/i  && !$caseSensitive) ) {
				if ($this->{spcTag} && $rule->{type} eq "spc")  {
					# if space chars are wrapped in <spc> tag
					my $spc=$1;
					$spc=~s/\n|\x0D?\x0A|\x0D/\\n/g;
					$spc=~s/\t/\\t/g;
					$result.="<".$this->{spcTag}." value='$spc' />";
				} elsif ( $rule->{type} eq "spc" && !$this->{printType}) {
					# in this case space chars are simply stuck to the previous form
					my $spc=$1;
					$result=~s/$this->{tokSeparator}$//;
					if ($spc=/^ +$/) {
						$result.= $spc;
					}
				} else {
					$result.= $1;
				}
				if ($this->{printType}) {
					$result.=$this->{typeSeparator}.$rule->{type};
				}
				$result.= $this->{tokSeparator};
				$string=$2;
				$found=1;
				last RULE_LOOP;
			}
		}
		if (! $found) {
			$this->printTrace("Infinite loop : $string\n"); # pour éviter une boucle infinie
			return 0;
		}
	}
	return $result;
}

#*************************************************************************** addParaTag()
# Add para tags <p id='sid'>...</p> for each end of line
# parameter :
# - noEmptyPara : boolean - if 1, consecutive ends of line will yield only one tag
# - xmlTag : do not process end of line in the context of <tag>
# - escapeMeta2Entities : if 1, transform < > and & in entities before processing

sub addParaTag {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($addParaTagDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	my $notInContextOfSup="";
	my $notInContextOfInf="";
	if ($this->{xmlTag}) {
		$notInContextOfSup="(?<!>)";
		$notInContextOfInf="(?!<)";
	}
	$this->printTrace("\n########### Adding <p> tags\n");
	my $searchReplacePatterns=[[qr/$notInContextOfSup(^|\r?\n|$)$notInContextOfInf/,'\n</p>\n<p id=\"p".($_++)."\">\n'],[qr/^\n<\/p>\n|\n<p id="[^"]*">\n$/,'']];
	if ($this->{noEmptyPara}) {
		$searchReplacePatterns=[[qr/$notInContextOfSup(^|(\s*\r?\n)+|$)$notInContextOfInf/,'\n</p>\n<p id=\"p".(++$_)."\">\n'],[qr/^\n<\/p>\n|\n<p id="[^"]*">\n$/,''],[qr/<p id="[^"]*">\s*<\/p>(\n|$)/,'']];
	}
	
	if ($this->{escapeMeta2Entities}) {
		unshift(@{$searchReplacePatterns},[qr/&/,"&amp;"],[qr/</,"&lt;"],[qr/>/,"&gt;"]);
	}
	
	$this->setParam( {
		searchReplacePatterns=>$searchReplacePatterns,
	},{overwriteParam=>1});
	
	$this->findAndReplace();

	# restoring the previous settings
	$this->restoreParam();
}

#*************************************************************************** search ()
# search an expression in a FORM CAT LEM CSV file (like treetagger)

#~ my $searchDefaultParam={
	#~ language=>'fr',			
	#~ outputConcord=> 1, 		# if 1, concord file is created, adding 'concord' to outputFileName
	#~ outputConcordFormat=>'',	# 'kwik' | 'XML'
	#~ outputIndex=> 1, 		# if 1, index file is created, adding 'index' to outputFileName
	#~ outputStat=> 1, 			# if 1, stat file is created, adding 'stat' to outputFileName
	#~ span=>40,				# number | 'sent'
	#~ spanUnit=>'char'			#
	#~ queries=>[''], 			# e.g. 'DET ADJ NOM' or '%faire NOM PRE' or '%avoir <>{,4} peur' or '%prendre PRE NOM'
	#~ queryFile=>'',			# a file with one query per line
	#~ countBy=>'', 			# 'query' | 'lemma' | 'form' | 'cat'
	#~ groupByFile=>1,			# if 1, all the results are grouped independtly for each files. If 0, all the data are merged
	#~ sortBy=>['F','expr']		# 'F'| 'expr' | 'right'| 'left'| 'pos' => 'F<' means  by ascending order of frequency for counted entries, 'F' means  by descending order of frequency, 'left' mean by the end of the left context
	#~ privateTagset=>{},			# a hash including specific tags used in the query

#~ };

sub search {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($searchDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});

	$this->printTrace("\n########### Executing function search()\n");
	
	$this->loadTagset();
	
	$this->{overwriteInput}=1;
	my $outputFileName=$this->handleNewFileName($this->{inputDir}."/search");

	if ($outputFileName eq "0" or $outputFileName eq "-1")  {
		return $outputFileName ;
	}
	
	# normalisation of format
	$this->{outputConcordFormat} =lc($this->{outputConcordFormat});

	# reading the queries file if necessary
	if ($this->{queryFile}) {
		if (open(QUERIES,$this->{queryFile})) {
			$this->printTrace("Reading queries from $this->{queryFile}\n");
			while (! eof(QUERIES)) {
				my $line=<QUERIES>;
				$line=~s/\x0D?\x0A?$//; # chomp
				$line=~s/\t#.*//; # suppress comment
				push(@{$this->queries},$line);
			}
			close(QUERIES);
		} else {
			$this->printTrace("Unable to open $this->{queryFile}\n",{warn=>1});
		}
	}
	
	my @queriesRegex;
	my $lang=$this->{language};
	# transforming the queries in regexp
	foreach my $query (@{$this->{queries}}) {
		my $r=$this->calcSearchPattern($query,$this->{tagset2TT}{$lang});
		
		push(@queriesRegex,qr/$r/);
	}
	

	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		my $span=$this->{span};
		my ($leftContext,$rightContext);
		
		if ($span eq "sent") {
			$leftContext=qr/<\/s>(?:.*?)/;
			$rightContext=qr/(?:.*?<\/s>)/;
		} else {
			$leftContext=qr/(?:[^\n]+\n){0,$span}/;
			$rightContext=qr/(?:[^\n]+\n){0,$span}/;
		}
		
		my @orderKeys=@{$this->{sortBy}};
		if ($this->{groupByFile}) {
			unshift(@orderKeys,'file');
		}
		
		if (open(INPUT,"<:encoding(".$this->{fileEncoding}.")",$fileName)) {
			$this->printTrace("----------------- Searching $fileName\n");

			my $text;
			$text=join("",<INPUT>);
			close(INPUT);

			my $i=0;
			# run the search using regexp !!!
			foreach my $queryRegex (@queriesRegex) {
				$this->printTrace("Searching $queryRegex\n");
				our @matches=(); #### Warning  -if only 'my', then @matches will not be shared in regex code (below)
				
				$text=~/(?>($queryRegex))(?>($rightContext))(?{ push(@matches,[$1,$2,$-[0]]) })(*FAIL)/g; # the (?>($queryRegex)) is 'independent' -> their wont be any backtracking for the context expression, once it has matched
				#print "span=$span, q=(?>($queryRegex))(?>($rightContext))- \ntext length=".length($text)." - searching  $query : ".@matches." matches\n";
				$this->printTrace(@matches." found !!!\n");
				foreach my $match (@matches) {
			
					#my $left=outputTokens($match->[0],$this->{outputConcordFormat});
					my $expr=outputTokens($match->[0],$this->{outputConcordFormat},$this->{tokenSeparator});
					my $right=outputTokens($match->[1],$this->{outputConcordFormat},$this->{tokenSeparator});
					my $pos=$match->[2];
					
					my $leftSpan=substr($text,$pos-$span*4,$span*4);
					$leftSpan=~/($leftContext)$/;
					my $left=outputTokens($1,$this->{outputConcordFormat},$this->{tokenSeparator});
					
					my $countKey=countKey($match->[0],$this->{countBy},$i);

					# formatting $left and $right to $span characters
					if ($this->{outputConcordFormat} eq "kwik" && $span ne "sent") {
						$left=(" "x$span).$left;
						$left=~s/^.*(.{$span})$/$1/;
						$right=$right.(" "x$span);
						$right=~s/^(.{$span}).*$/$1/;
					}
					
					# update of stat results
					if ($this->{groupByFile}) {
						if (!exists($searchResults{stat}{$fileName})) {
							$searchResults{stat}{$fileName}={};
						}
						$searchResults{stat}{$fileName}{$countKey}++;
					} else {
						$searchResults{stat}{$countKey}++;
					}
					# update of index results
					if (!exists($searchResults{index}{$fileName})) {
						$searchResults{index}{$fileName}={};
					}
					if (!exists($searchResults{index}{$fileName}{$countKey})) {
						$searchResults{index}{$fileName}{$countKey}=[];
					}
					push(@{$searchResults{index}{$fileName}{$countKey}},$pos);
					
					# update of concord results
					my $concordEntry={'left'=>$left,'expr'=>$expr,'right'=>$right,'pos'=>$pos,'F'=>$countKey, 'file'=>$fileName};
					my @keys;
					# looping through complete results and building the final hash sortKey->concord list
					foreach my $orderKey (@orderKeys) {
						if ($orderKey eq "F<") { 
							push(@keys,$concordEntry->{'F'});
						} else {
							push(@keys,$concordEntry->{$orderKey});
						}
					}
					my $key=join("\t",@keys);
					
					if (!exists($searchResults{concord}{$key})) {
						$searchResults{concord}{$key}=[];
					}
					push(@{$searchResults{concord}{$key}},$concordEntry);
				}
				$i++;
			}
		}
		return 1;
	};
	
	# reinit the result tab
	$searchResults{stats}={};
	$searchResults{concord}={};
	$searchResults{index}={};
	
	# run !
	$this->printTrace("Running search\n");
	my $res= $this->process('Searching patterns');
	
	
	# printing concord
	if ($this->{outputConcord}) {
		my @orderKeys=@{$this->{sortBy}};
		if ($this->{groupByFile}) {
			unshift(@orderKeys,'file');
		}
		
		if(open(OUTPUT,">:encoding(".$this->{fileEncoding}.")",$outputFileName.".concord")) {
			$this->printTrace("Creating output $outputFileName.concord\n");
			my $oldFileName;

			foreach my $key (sort { orderConcord(@orderKeys) } keys %{$searchResults{concord}}) {
				if ($this->{groupByFile}) {
					$key=~/^(.*?)\t/;
					my $fileName=$1;
					if ($fileName ne $oldFileName) {
						if ($this->{outputConcordFormat} eq "xml") {
							if ($oldFileName) {
								print OUTPUT "</text>\n";
							}
							print OUTPUT "<text id='$fileName'>\n";
						} else {
							print OUTPUT "=============================> $fileName\n\n";
						}
						$oldFileName=$fileName;
					}
				}
				
				foreach my $concordEntry (@{$searchResults{concord}{$key}}) {

					if ($this->{outputConcordFormat} eq "xml") {
						print OUTPUT "<chunk pos='".$concordEntry->{file}."/".$concordEntry->{pos}."' countBase='".$concordEntry->{F}."'>\n";
						print OUTPUT "<div type='left'>\n";
						print OUTPUT $concordEntry->{left}."\n";
						print OUTPUT "</div>\n";
						print OUTPUT "<div type='expr'>\n";
						print OUTPUT $concordEntry->{expr}."\n";
						print OUTPUT "</div>\n";
						print OUTPUT "<div type='right'>\n";
						print OUTPUT $concordEntry->{right}."\n";
						print OUTPUT "</div>\n";
						print OUTPUT "</chunk>\n";
					} else {
						print OUTPUT $concordEntry->{left}."\t".$concordEntry->{expr}."\t".$concordEntry->{right}."\t".$concordEntry->{file}."/".$concordEntry->{pos}."\t".$concordEntry->{F}."\n";
					}
				}
			}
			if ($this->{groupByFile} && $this->{outputConcordFormat} eq "xml") {
				print OUTPUT "</text>\n";
			}
			close(OUTPUT);
		} else {
			$this->printTrace("Unable to create $outputFileName.concord\n",{warn=>1});
		}
	}
	
	# printing stats if necessary
	if ($this->{outputStat}) {
		# only the order keys "expr", "F" and "F<" are taken into account
		my @orderKeys=grep {/^(expr|F)/} @{$this->{sortBy}};
				
		if(open(OUTPUT,">:encoding(".$this->{fileEncoding}.")",$outputFileName.".stat")) {
			$this->printTrace("Creating output $outputFileName.stat\n");
			if ($this->{groupByFile}) {
				foreach my $fileName (sort keys %{$searchResults{stat}}) {
					print OUTPUT "=============================> $fileName\n\n";
					
					foreach my $key (sort { orderStat($searchResults{stat}{$fileName},@orderKeys) } keys %{$searchResults{stat}{$fileName}}) {
						print OUTPUT $key."\t".$searchResults{stat}{$fileName}->{$key}."\n";
					}
				}
			} else {
				foreach my $key (sort { orderStat($searchResults{stat},@orderKeys) } keys %{$searchResults{stat}}) {
					print OUTPUT $key."\t".$searchResults{stat}->{$key}."\n";
				}
			}
			close(OUTPUT);
		} else {
			$this->printTrace("Unable to create $outputFileName.stat\n",{warn=>1});
		}
	}
	$this->restoreParam();
}



# condord entries order routine
sub orderConcord {
	my @orderKeys=@_;
	my @a=split(/\t/,$a);
	my @b=split(/\t/,$b);
	my $i=0;

	foreach my $orderKey (@orderKeys) {
		# for F the value is in the stat hash
		if( $orderKey eq 'F') {
			if ($searchResults{stat}{$b[$i]} <=> $searchResults{stat}{$a[$i]}) {
				return $searchResults{stat}{$b[$i]} <=> $searchResults{stat}{$a[$i]};
			}
		} elsif ( $orderKey eq 'F<') {
		# F with ascending order
			if ($searchResults{stat}{$a[$i]} <=> $searchResults{stat}{$b[$i]}) {
				return $searchResults{stat}{$a[$i]} <=> $searchResults{stat}{$b[$i]};
			}
		} elsif ( $orderKey eq 'left') {
		# for left context, the order is by the end of the string 
			if (reverse($a[$i]) cmp reverse($b[$i])) {
				return reverse($a[$i]) cmp reverse($b[$i]);
			}
		} elsif ($orderKey eq 'pos') {
		# text position
			if ($a[$i] <=> $b[$i]) {
				return $a[$i] <=> $b[$i];
			}
		} else  {
		# general case : alphanumeric ascending order
			if ($a[$i] cmp $b[$i]) {
				return $a[$i] cmp $b[$i];
			}
		}
		$i++;
	}
	return 0;
}

# stat entries order routine
sub orderStat {
	my $hash=shift;
	my @orderKeys=@_;
	
	foreach my $orderKey (@orderKeys) {
		# for F the value is in the stat hash
		if( $orderKey eq 'F') {
			if ($hash->{$b} <=> $hash->{$a}) {
				return ($hash->{$b} <=> $hash->{$a});
			}
		} elsif ( $orderKey eq 'F<') {
			if ($hash->{$a} <=> $hash->{$b}) {
				return $hash->{$a} <=> $hash->{$b};
			}
		} else {
			if ($a cmp $b) {
				return $a cmp $b;
			}
		}
	}
	return 0;
}

#***************************** compute collocations and/or repeated segments
# Parameters
# - inputFormat : "tt" or "CoNLL"
# - coocSpan : integer - indicates the size (in word) of the sliding window - o=no computation
# - coocSpan : string - "sent", "para", "text", "depRel"
# - recordRel : boolean - if 1 record the relation entry1.rel.entry2, if not record only the two cooccurring form. When recordRel, the rel occurrence freq is recorded as well
# - repeatedSegmentsMaxLength - indicates the size (in word) of the sliding window - 0= nocomputation
# - insideSent : boolean - indicates whether the cooccurrence span is limited by sentence boundary (=1) or not (=0)
# - countBy : string ('lemma'|'form'|'cat'|'form_cat'|'lemma_cat') - indicates which feature is used to represent expressions in statistics
# - coocTable : string - the name of the collocation table (DBM or not), and of the outputFile
# - repeatedSegments :  string - the name of the repeatedSegments table (DBM or not), and of the outputFile
# - orderSensitive : boolean - if 1, cooccurrence of c1..c2 is not identical to c2..c1 - if 0, c1..c2 = c2..c1 (which means that the real cooc span is 2*span-1 because it represents [-span...+span])
#		for syntactic cooccurrence, the order is head->dep. When not ordersensitive, the order is alphabetical
# - toLowerCase : boolean - if 1, every entry is lowercased in the table
# - useDbm : boolean - indicates if coocTable and repeatedSegments should be saved in a dbm file
# - useSimplifiedTagset : boolean - indicates if the tagset has to translated into simplified tagset
# - tagsetName : string - the name of the tagset to translate (default is 'tagsetTreetagger')
# - catPattern : [/regex/,string] - a category pattern transformation scheme eq [qr/(.*?):.*/,'$1']
# - vocIncreaseStep : integer - every 'step' occurrences, the vocabulary increase is recorded (the vocSize is pushed)
# - entrySep : string - by default "_" : glue for lemma_cat concatenation
# - printNbLines : boolean - to follow the reading process
# - c1Pattern : pattern - to reduce the cooccurrence space to a certain type of collocate 1 (e.g. qr/.*_NOM/) to get noun, if countBy = 'lemma_cat' in extractCollocation() ouput
# - c2Pattern : pattern - to reduce the cooccurrence space to a certain type of collocate 2 (e.g. qr/.*_NOM/) to get noun, if countBy = 'lemma_cat' in extractCollocation() ouput
# - relPattern : pattern - to reduce the cooccurrence space to a certain type of dependency relation 
# - minCoocFreq : integer - minimum cooccurrence frequency to record in the hash

# The fields that may be in the output are : c1, c2, f1, f2, f12, log-like, pmi, t-score, z-score

# - filterBy : list ref - define criteria to filter results lines - ['f12>10','f1>4','log-like>=10.83'] - 
# - orderBy : ['l1','log-like'] - define the multiple sorting key for the results - Add ">" for descending et "<" for ascending
# - displayColumns : ['c1','log-like','c2'] - the column that have to be in the output

# Output
# - the dbm files (coocTable et repeatedSegments)
# - coocTableHash -> contains both occurrence and cooccurrence frequencies (used even if no coocSpan)
			# key with no tab : simple occurrence frequency
			# tab.key : occurrence frequency in the cooccurrence space
			# key.tab : occurrence frequency on the left side if orderSensitive
			# key1.tab.key2 : cooccurrence frequency in the cooccurrence space
			# key1.tab.rel.tab.key2 : cooccurrence frequency with the relation rel
			# tab.rel.tab : occurrence frequency of rel
			# __coocSpaceSize__ : the complete cooc space size
# - repeatedSegmentHash
# - globalStatsHash
# Param are not saved !!!!

sub extractCoocTable {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	#~ $this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($extractCoocTableDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	$this->printTrace("\n########### Executing function extractCoocTable()\n");

	if (! $this->{c1Pattern}) {
		$this->{c1Pattern}=[qr/.*/];
	}
	if (! $this->{c2Pattern}) {
		$this->{c2Pattern}=[qr/.*/];
	}

	# loading simplified tagset if necessary
	if ($this->{useSimplifiedTagset}) {
		$this->loadTagset();
	}
	
	# initialization of occTable hash
	$this->{oocTableHash}={};
	# initialization of coocTable hash
	$this->{coocTableHash}={};
	$this->{coocTableHash}{'__coocSpaceSize__'}=0;
	$this->{coocTableHash}{'__docFreq__'}={};
	# initialization of repeatedSegments hash
	$this->{repeatedSegmentsHash}={};
	$this->{repeatedSegmentsHash}{'__docFreq__'}={};
	# initialization of global stats
	$this->{globalStatsHash}={};
	$this->{globalStatsHash}{tokNum}=0;
	$this->{globalStatsHash}{charNum}=0;
	$this->{globalStatsHash}{sentNum}=0;
	$this->{globalStatsHash}{paraNum}=0;
	$this->{globalStatsHash}{textNum}=0;
	$this->{globalStatsHash}{vocSize}=0;
	# if vocabulary increase has to be recorded
	if ($this->{vocIncreaseStep}) {
		$this->{vocIncrease}=[];
	}
	# if morphosyntactic features has to be recorded
	if ($this->{features2record}) {
		$this->{featuresHash}={};
	}
	

	my ($newFileNameCooc,$newFileNameRepeatedSegments);

	my $totalFreq=0;
	
	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		my $res=1;
		
		$this->printTrace("Reading $fileName ($this->{fileEncoding})\n");

		if (open(FILE,"<:encoding(".$this->{fileEncoding}.")",$fileName)) {
			my @coocSpan;
			my @repeatedSegmentsSpan;

			my $id2entry={};
			my $nbLines=0;
			while (! eof(FILE)) {
				my $line=<FILE>;
				$nbLines++;
				if ($this->{printNbLines}&& $nbLines % 10000==0) {
					print "Line : $nbLines...\n";
				}
						
				$line=~s/\x0D?\x0A?$//;
				my ($id,$form,$lemma,$catFea,$cat2,$fea,$head,$depRel,$deps);
				my $sent=0;
				my $tok=0;
				my $para=0;
				my $text=0;

				if ($this->{inputFormat}=~/conll/i) {
					if ($line eq "") {
						$sent=1;
					} else {
						# reading a token line
						my @fields=split(/\t/,$line);
						if (@fields>=8) {
							($id,$form,$lemma,$catFea,$cat2,$fea,$head,$depRel,$deps)=@fields;
							# !!! deps is not yet used
							if ($head eq "_") {
								$head="";
							}
							if ($depRel eq "_") {
								$depRel="";
							}
							$tok=1;
						}
					}
				} elsif ($line=~/^(.*)\t(.*)\t(.*)/) {
					# reading a token line : Treetagger format
					($form,$catFea,$lemma)=($1,$2,$3);
					$tok=1;
					if ($catFea eq $this->{sentMark}) {
						$sent=1;
					}
				}
				
				# updating stats when a token has been read
				if ($tok) {
					$totalFreq++;
					my $entry=$this->calcEntry([$form,$catFea,$lemma]);
					#~ print $entry."\n";
					if ($id ne "") {
						# for conll format, entries are associated to their id
						$id2entry->{$id}=$entry;
					}
	
					# single occurrences stats
					# incrementing vocabulary size
					if (! defined($this->{coocTableHash}{toBytes($entry)})) {
						$this->{globalStatsHash}{vocSize}++;
					}
					# recording vocIncrease
					if ($this->{vocIncreaseStep} && ($this->{globalStatsHash}{tokNum} % $this->{vocIncreaseStep})==0) {
						push(@{$this->{vocIncrease}},$this->{globalStatsHash}{vocSize});
					}
					# incrementing token frequency
					$this->{coocTableHash}{toBytes($entry)}++;
					$this->{coocTableHash}{'__docFreq__'}{toBytes($entry)}{$fileName}=1;
					
					
					
					push(@coocSpan,[$id,$form,$catFea,$lemma,$head,$depRel]) if ($this->{coocSpan});
					push(@repeatedSegmentsSpan,[$form,$catFea,$lemma]) if ($this->{repeatedSegmentsMaxLength});
					# updating global stats
					$this->{globalStatsHash}{tokNum}++;
					$this->{globalStatsHash}{charNum}+=length($form);
					if ($this->{features2record}) {
						foreach my $cat (keys %{$this->{features2record}}) {
							my $re=$this->{features2record}{$cat};
							if ($catFea=~/($this->{features2record}{$cat})/) {
								my $fea=$1;
								$this->{featuresHash}{$cat}{$fea}++;
							}
						}
					}
				} elsif ($line=~/<\/p\s*>/) {
					$this->{globalStatsHash}{paraNum}++;
					$para=1;
				} elsif ($line=~/<\/text\s*>/) {
					$this->{globalStatsHash}{textNum}++;
					$text=1;
				}
				# updating sentence stats
				$this->{globalStatsHash}{sentNum}++ if ($sent);

				# processing cooccurrences
				if ($this->{coocSpan}) {
					if ( 	($sent && $this->{coocSpan} =~/sent/i ) 
						||	($sent && $this->{coocSpan} =~/deprel/i )
						||	($para && $this->{coocSpan} =~/para/i )
						||	($text && $this->{coocSpan} =~/text/i )
						||	($this->{coocSpan} =~/\d+/ && @coocSpan >= $this->{coocSpan})) {
						#~ print "coocSpan=$this->{coocSpan}  para=$para sent=$sent coocSpan= @coocSpan\n";	
						$this->shiftCoocSpan(\@coocSpan,$id2entry);
					}
				}
				# if a sentence has been processed $id2entry hash is cancelled
				if ($sent && $this->{coocSpan} =~ /deprel/i ) {
					$id2entry={};
				}
				# processing repeatedSegment
				if ($this->{repeatedSegmentsMaxLength} && @repeatedSegmentsSpan >= $this->{repeatedSegmentsMaxLength}) {
					$this->shiftRepeatedSegment(\@repeatedSegmentsSpan,$fileName);
				}
			}
			# processing the end of @coocSpan stack
			# text spans are processed here !!!  
			while ($this->{coocSpan} && @coocSpan) {
				#~ print "coocSpan=$this->{coocSpan}  coocSpan= @coocSpan\n";	
				$this->shiftCoocSpan(\@coocSpan,$id2entry);
			}
			# processing the end of @repeatedSegmentsSpan stack
			while ($this->{repeatedSegmentsMaxLength} && @repeatedSegmentsSpan) {
				$this->shiftRepeatedSegment(\@repeatedSegmentsSpan);
			}
			print "DONE!\n";
			close(FILE);
		} else {
			$this->printTrace("Unable to open $fileName\n");
			$res=0;
		}
		return $res;
	};
	
	# run !
	my $res = $this->process('Cooccurrence table extraction');
	
	$this->{coocTableHash}{'__totalFreq__'}=$totalFreq;
	#~ untie %coocTable;
	if ($this->{useDbm}) { 
		# opening dbmFile for coocTable
		if ($this->{coocSpan}) {
			
			$newFileNameCooc=$this->{outputDir}."/".$this->{coocTable};
			# creating file directory
			if ($this->createDir($newFileNameCooc)==-1) {
				return -1;
			}
			if (! $useDbFile) {
				my $newFileNamePag=$this->ifFileExistBackupOrAbort($newFileNameCooc.".pag");
				my $newFileNameDir=$this->ifFileExistBackupOrAbort($newFileNameCooc.".dir");
				if ($newFileNamePag eq "0" or $newFileNameDir eq "0") {
					$this->printTrace($this->{outputDir}."/$newFileNameCooc.pag already exists and overwriteOutput=0 : operation is aborted\n",{warn=>1});
					return 0;
				}
				if (-f $newFileNamePag) {
					$this->printTrace("Deleting existing table $newFileNamePag\n",{warn=>1});
					unlink $newFileNamePag;
					unlink $newFileNameDir;
				}
			} else {
				$newFileNameCooc=$this->ifFileExistBackupOrAbort($newFileNameCooc.".dat");
				if ($newFileNameCooc eq "0") {
					$this->printTrace($this->{outputDir}."/".$this->{coocTable}." already exists and overwriteOutput=0 : operation is aborted\n",{warn=>1});
					return 0;
				}
				if (-f $newFileNameCooc) {
					$this->printTrace("Deleting existing table $newFileNameCooc\n",{warn=>1});
					unlink $newFileNameCooc;
				}
			}

			my %coocTable;
			if ( ! dbmOpen (\%coocTable,$newFileNameCooc,0777)) {
				$this->printTrace("Unable to create dbm file : $newFileNameCooc\n",{warn=>1});
				return 0;
			}
			$this->printTrace("Saving cooccurrence hash in dbm file  $newFileNameCooc\n");
			my $nbKeys=0;
			while (my ($key,$val)=each(%{$this->{coocTableHash}})) {
				if ($val >= $this->{minCoocFreq}) {
					$nbKeys++;
					$coocTable{$key}=$val;
				}
			}
			$this->printTrace("$nbKeys keys recorded in dbm file  $newFileNameCooc\n");
			#~ print "__coocSpaceSize__=".$coocTable{"__coocSpaceSize__"}." - ".$this->{coocTableHash}{'__coocSpaceSize__'}."\n";
			dbmClose(\%coocTable);
		} 
		
		# opening dbmFile for repeatedSegmentsHash
		if ($this->{repeatedSegmentsMaxLength}  && $this->{repeatedSegments}) {
			$newFileNameRepeatedSegments=$this->{outputDir}."/".$this->{repeatedSegments};
			# creating file directory
			if ($this->createDir($newFileNameRepeatedSegments)==-1) {
				return -1;
			}
			if (! $useDbFile) {
				my $newFileNamePag=$this->ifFileExistBackupOrAbort($newFileNameRepeatedSegments.".pag");
				my $newFileNameDir=$this->ifFileExistBackupOrAbort($newFileNameRepeatedSegments.".dir");
				if ($newFileNamePag eq "0" or $newFileNameDir eq "0") {
					$this->printTrace($this->{outputDir}."/".$this->{repeatedSegments}." already exists and overwriteOutput=0 : operation is aborted\n",{warn=>1});
					return 0;
				}
				if (-f $newFileNamePag) {
					$this->printTrace("Deleting existing table $newFileNameRepeatedSegments\n",{warn=>1});
					unlink $newFileNamePag;
					unlink $newFileNameDir;
				}
			} else {
				$newFileNameRepeatedSegments=$this->ifFileExistBackupOrAbort($newFileNameRepeatedSegments.".dat");
				if ($newFileNameRepeatedSegments eq "0") {
					$this->printTrace($this->{outputDir}."/".$this->{repeatedSegments}." already exists and overwriteOutput=0 : operation is aborted\n",{warn=>1});
					return 0;
				}
				if (-f $newFileNameRepeatedSegments) {
					$this->printTrace("Deleting existing table $newFileNameRepeatedSegments\n",{warn=>1});
					unlink $newFileNameRepeatedSegments;
				}
			}
			
			my %repeatedSegmentsHash;
			if ( ! dbmOpen (\%repeatedSegmentsHash,$newFileNameRepeatedSegments,0777)) {
				$this->printTrace("Unable to create dbm file : $newFileNameRepeatedSegments\n",{warn=>1});
				return 0;
			}
			
			$this->printTrace("Saving repeated segments hash in dbm file  $newFileNameRepeatedSegments\n");
			while (my ($key,$val)=each(%{$this->{repeatedSegmentHash}})) {
				if ($key ne "__docFreq__") {
					$repeatedSegmentsHash{$key}=$val;
				}
			}
			dbmClose(\%repeatedSegmentsHash);
		}
	}
	
	#~ $this->restoreParam();
	return $res;
}


# update coocTableHash counting the cooccurrences inside the current span - then shift the span
sub shiftCoocSpan {
	my $this=shift;
	my $span=shift;
	my $id2entry=shift;
			
	my $tok1=shift(@{$span});
	my $entry1=$this->calcEntry([$tok1->[1],$tok1->[2],$tok1->[3]]);
	

	if ($this->{coocSpan} =~ /deprel/i) {
		my $id1=$tok1->[0];
		my $head=$tok1->[4];
		my $depRel=$tok1->[5];

		if (exists($id2entry->{$head})) {
			my $entry2=$id2entry->{$head};
			if ($entry2=~$this->{c1Pattern}[0] && $entry1=~$this->{c2Pattern}[0] && $depRel=~$this->{relPattern}[0] ) {
				$this->{coocTableHash}{'__coocSpaceSize__'}++; # number of occurrences of the relation

				# incrementing cooccurrence frequency
				if ($this->{orderSensitive}) {
					if ($this->{recordRel}) {
						$this->{coocTableHash}{toBytes($entry2."\t$depRel\t".$entry1)}++;
						$this->{coocTableHash}{"\t$depRel\t"}++; # number of occurrences of the relation
					} else {
						$this->{coocTableHash}{toBytes($entry2."\t".$entry1)}++;
					}
					$this->{coocTableHash}{toBytes("\t".$entry1)}++; # number of occurrences as dependant
					$this->{coocTableHash}{toBytes($entry2."\t")}++; # number of occurrences as governor
				} else {
					my ($e1,$e2)=sort($entry1,$entry2);
					if ($this->{recordRel}) {
						$this->{coocTableHash}{toBytes($e1."\t$depRel\t".$e2)}++;
						$this->{coocTableHash}{"\t$depRel\t"}++; # number of occurrences of the relation
					} else {
						$this->{coocTableHash}{toBytes($e1."\t".$e2)}++;
						$this->{coocTableHash}{toBytes("\t".$e1)}++; # number of occurrences as dependant
						$this->{coocTableHash}{toBytes("\t".$e2)}++; # number of occurrences as governor
					}
				}
			}
		} else {
			#~ print "pas d'id trouvé pour $head avec $depRel\n";
		}
	} elsif ($entry1=~ $this->{c1Pattern}[0]) {

		FORSPAN:for (my $i=0;$i<@{$span};$i++) {
			my ($id2,$form2,$catFea2,$lemma2,$head2,$depRel2)=@{$span->[$i]};
			my $entry2=$this->calcEntry([$form2,$catFea2,$lemma2]);
			
			if ($id2==1 && $this->{insideSent}) {
				last FORSPAN;
			}
			if ($entry2=~$this->{c2Pattern}[0]) {
				$this->{coocTableHash}{'__coocSpaceSize__'}++; # number of occurrences of the relation
				
				# incrementing cooccurrence frequency
				if ($this->{orderSensitive}) {
					$this->{coocTableHash}{toBytes($entry1."\t".$entry2)}++;
					$this->{coocTableHash}{toBytes("\t".$entry2)}++; # number of occurrences as dependant
					$this->{coocTableHash}{toBytes($entry1."\t")}++; # number of occurrences as governor
				} else {
					my ($e1,$e2)=sort($entry1,$entry2);
					$this->{coocTableHash}{toBytes($e1."\t".$e2)}++;
					$this->{coocTableHash}{toBytes("\t".$e1)}++; # number of occurrences as dependant
					$this->{coocTableHash}{toBytes("\t".$e2)}++; # number of occurrences as governor
				}
				
				if ($span->[$i]->[1] eq $this->{sentMark} && $this->{insideSent}) {
					last FORSPAN;
				}
			}
		}
	}
	# if the window is not sliding, recursion
	if ($this->{coocSpan} =~/deprel|sent|para|text/i && @{$span}) {
		$this->shiftCoocSpan($span,$id2entry);
	}
}
# update repeatedSegmentsHash counting the cooccurrences inside the current span - then shift the span
sub shiftRepeatedSegment {
	my $this=shift;
	my $span=shift;
	my $fileName=shift;
			
	my $tok=shift(@{$span});
	my $entry=$this->calcEntry($tok);
	
	# incrementing token frequency
	my @toks=($entry);
	
	for (my $i=0;$i<@{$span};$i++) {
		push(@toks,$this->calcEntry($span->[$i]));

		$this->{repeatedSegmentsHash}{toBytes(join(" ",@toks))}++;
		$this->{repeatedSegmentsHash}{'__docFreq__'}{toBytes(join(" ",@toks))}{$fileName}=1;
		if ($span->[$i]->[1] eq "SENT" && $this->{insideSent}) {
			last;
		}
	}
}


# compute the form of table entry (statistics are computed for these)
# category may be translated into simplified tagset
sub calcEntry {
	my $this=shift;
	my $tok=shift;
	my ($form,$cat,$lemma)=@{$tok};
	if ($this->{catPattern}) {
		$cat=~s/$this->{catPattern}[0]/$this->{catPattern}[1]/ee;
	}
	my $entry;
	my $lang=$this->{language};
	
	if ($this->{useSimplifiedTagset}) {
		if (exists($this->{TT2tagset}{$lang}{$cat})) {
			$cat=$this->{TT2tagset}{$lang}{$cat};
		}
	}

	
	if ($this->{countBy} eq "form") {
		$entry=$form;
	} elsif ($this->{countBy} eq "cat") {
		$entry=$cat;
	} elsif ($this->{countBy} eq "lemma") {
		$entry=$lemma;
	} elsif ($this->{countBy} eq "form_cat") {
		$entry=$form.$this->{entrySep}.$cat;
	} else {
		$entry=$lemma.$this->{entrySep}.$cat;
	} 
	if ($this->{toLowerCase}) {
		return lc($entry);
	}
	return $entry;
}

#*************************************************************************** displayCollocations ()
# - useDbm : indicates if dbmFile has to be open
# - coocTable : string - the name of the collocation table (DBM or not), and of the outputFile
# - orderSentitive : boolean - indicates whether the order of (c1,c2) collocation has to be taken into account
# - removalListFile : string - file that contains forms to ignore

# The fields that may be in the output are : c1, c2, f1, f2, f12, log-like, pmi, t-score, z-score
# - c1Pattern : [pattern,string]	- the pattern is used to filter the form of collocate 1 (e.g. qr/(.*_N)/) to get noun, if countBy = 'lemma_cat' in extractCollocation() ouput 
#									- the string (optional) may contain perl code to replace the captured substring in order to group collocates (e.g. 'lc($1)' to transform into lowercase and to keep only the first letter of POS). 
# - c2Pattern : [pattern,string] - same as c1Pattern - not used if orderSensitive==0
# - relPattern : [pattern,string] - same as c1Pattern
# - groupFilter : boolean - indicates if a filter is used to group entries and relations
# - groupReportFile : string name of the file groupReport
# - groupReportHeader : boolean
# - groupReportKeys : [string*] - the keys are the result of groupBy pattern applied to entry1 and entry2. For instance, it may be 'N_N', 'N_V', 'V_A' if groupBy extract POS first char
# - groupBy : [pattern,string] - same as c1Pattern [qr/.*_(\w).*/,'$1']
# - filterBy : list ref - define criteria to filter results lines - ['f12>10','f1>4','log-like>=10.83'] - CAUTION : use == for equal (not = )
# - orderBy : ['l1','log-like'] - define the multiple sorting key for the results. Add ">" for descending et "<" for ascending
# - displayColumns : ['c1','c2','f1','f2','f12','rel','log-like','pmi','t-score','z-score'] - the column that have to be in the output
# - useDbm : indicates whether the table hash is in dbm or not - if not the table MUST be in $this->{coocTableHash}


# Note : The cooccurrence table must have been previously extracted by extractCoocTable()

sub displayCollocations {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($displayCollocationsDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
		
	$this->printTrace("\n########### Executing function displayCollocations()\n");

	if (! $this->{coocSpan}) {
		$this->printTrace("Operation aborted : coocSpan value is null\n",{warn=>1});
		return 0;
	}
	if (! $this->{c1Pattern}) {
		$this->{c1Pattern}=[qr/.*/];
	}
	if (! $this->{c2Pattern}) {
		$this->{c2Pattern}=[qr/.*/];
	}

	# reading the removal list
	my %removalList;
	if  ($this->{removalListFile}) {
		if (open(REMOVAL,"<:encoding(utf8)",$this->{removalListFile})) {
			while (! eof(REMOVAL)) {
				my $line=<REMOVAL>;
				chomp $line;
				$removalList{$line}=1;
			}
		} else {
			$this->printTrace("Unable to open $this->{removalListFile} : NO REMOVAL LIST WILL BE READ\n",{warn=>1});
		}
	}
	
	# opening Group Report file
	my $groupReport=0;
	if ($this->{groupReportFile}) {
		if (open(GROUPREPORT,">>:encoding(utf8)",$this->{outputDir}."/".$this->{groupReportFile})) {
			$groupReport=1;
			if ($this->{groupReportHeader}) {
				print GROUPREPORT "file\tSize";
				foreach my $col (@{$this->{groupReportKeys}}) {
					print GROUPREPORT "\t$col:occ\t$col:types\t$col:refFreq";
				}
				print GROUPREPORT "\n";
			}
		} else {
			$this->printTrace("Unable to open $this->{groupReportFile} in write mode\n",{warn=>1});
		}
	}

	my $outputFileName=$this->handleNewFileName($this->{outputDir}."/".$this->{coocTable});
	if ($outputFileName eq "0" or $outputFileName eq "-1")  {
		return $outputFileName ;
	}

	my $res=1;
	
	if (open(OUTPUT,">:encoding(".$this->{fileEncoding}.")",$outputFileName)) {
		$this->printTrace("Writing $outputFileName\n");
		if (!$this->{useDbm} &&  ! $this->{coocTableHash} ) {
			$this->printTrace("\%coocTableHash is empty\n",{warn=>1});
			return 0;
		}
		if ($this->{useDbm}) {
			$this->{coocTableHash}={};
			my $suff="";
			if ($useDbFile) {
				$suff=".dat";
			}
			if (! dbmOpen ($this->{coocTableHash},$this->{inputDir}."/".$this->{coocTable}.$suff,0777)) {
				$this->printTrace("Unable to open dbm file : ".$this->{inputDir}."/".$this->{coocTable}.$suff."\n",{warn=>1});
				return 0;
			} else {
				$this->printTrace("Opening the dbm file : ".$this->{inputDir}."/".$this->{coocTable}.$suff."\n");
			}
		}

		if ($this->{collocListFile}) {
			dbmOpen (\%collocList,$this->{collocListFile},0777);
			#~ tie (%collocList,"DB_File",$this->{collocListFile},O_RDONLY);
		}
		my $coocSpaceSize=$this->{coocTableHash}{'__coocSpaceSize__'};
		
		if (! $coocSpaceSize) {
			$this->printTrace("Operation aborted (coocSpaceSize=$coocSpaceSize): the table is empty or corrupted (file = $this->{inputDir}/$this->{coocTable})\n",{warn=>1});
			while (my ($k,$v) =each(%{$this->{coocTableHash}})) {
				print "$k => $v\n";
			}
			return 0;
		}

		my @results;
		
		# computing the expression for line filtering
		my $filteringExpr=1;
		foreach my $c (@{$this->{filterBy}}) {
			my $filteringCriterion = $c;
			$filteringCriterion=~s/(c1|c2|f12|f1|f2|log-like|z-score|t-score|pmi|matchList|freqRel)/\$line->{'$1'}/g;
			$filteringExpr.=" && (".$filteringCriterion.")";
		}
		
		my $coocTable=$this->{coocTableHash};
		my $groupedCoocTable={};
		my %groupReportCoocTable={};
		my $noDecode=0; 	# if a new coocTable is extracted by grouping, no need to decode. 
		
		# grouping the keys according to c1Pattern and c2Pattern transformation) - For instance $this->{c1Pattern}=[qr/(.*_\w).*/,'lc($1)']
		if ($this->{groupFilter} && ($this->{c1Pattern}[1] || $this->{c2Pattern}[1] || $this->{relPattern}[1])) {
			while (my ($key,$value)=each(%{$this->{coocTableHash}})) {
				
				my ($keyType,$entry,$entry1,$entry2,$rel);
				if ($key=~/^\t([^\t]+)$/) {
					$keyType= "entryRight";
					$entry=decode($this->{fileEncoding},$1);
				} elsif ($key=~/^([^\t]+)\t$/) {
					$keyType= "entryLeft";
					$entry=decode($this->{fileEncoding},$1);
				} elsif ($key=~/^\t([^\t]+)\t$/) {
					$keyType= "rel";
					$rel=decode($this->{fileEncoding},$1);
				} elsif ($key=~/^([^\t]+)\t([^\t]+)$/) {
					$keyType= "entry1Entry2";
					$entry1=decode($this->{fileEncoding},$1);
					$entry2=decode($this->{fileEncoding},$2);
				} elsif ($key=~/^([^\t]+)\t([^\t]+)\t([^\t]+)$/) {
					$keyType= "entry1RelEntry2";
					$entry1=decode($this->{fileEncoding},$1);
					$rel=decode($this->{fileEncoding},$2);
					$entry2=decode($this->{fileEncoding},$3);
				}
				# computing new relation if necessary
				my $newRel=$rel;
				if ($rel && $this->{relPattern}[1]) {
					$newRel=~s/$this->{relPattern}[0]/$this->{relPattern}[1]/ee;
				}

				# grouping occurrences
				if ($this->{orderSensitive}) {
					if ($keyType eq "entryRight" && $entry =~$this->{c2Pattern}[0] ) {
						my $newC2=$entry; 
						if ($this->{c2Pattern}[1]) {
							$newC2=~s/$this->{c2Pattern}[0]/$this->{c2Pattern}[1]/ee;
						}
						$groupedCoocTable->{"\t".$newC2}+=$value;
					} elsif ($keyType eq "entryLeft" && $entry =~$this->{c1Pattern}[0] ) { 
						my $newC1=$entry;
						if ($this->{c1Pattern}[1]) {
							$newC1=~s/$this->{c1Pattern}[0]/$this->{c1Pattern}[1]/ee;
						}
						$groupedCoocTable->{$newC1."\t"}+=$value;
					} elsif ($entry1 && $entry1 =~$this->{c1Pattern}[0] && $entry2 =~$this->{c2Pattern}[0]) {
						my $newC1=$entry1;
						my $newC2=$entry2;
						if ($this->{c1Pattern}[1]) {
							$newC1=~s/$this->{c1Pattern}[0]/$this->{c1Pattern}[1]/ee;
						}
						if ($this->{c2Pattern}[1]) {
							$newC2=~s/$this->{c2Pattern}[0]/$this->{c2Pattern}[1]/ee;
						}
						if ($keyType eq "entry1RelEntry2") {
							$groupedCoocTable->{$newC1."\t".$newRel."\t".$newC2}+=$value;
						} else {
							$groupedCoocTable->{$newC1."\t".$newC2}+=$value;
						}
					} elsif ($keyType eq "rel") {
						$groupedCoocTable->{"\t".$newRel."\t"}+=$value;
					} else {
						# nothing to change (rel or tot)
						$groupedCoocTable->{$key}=$value;
					}
					
				} else {
					if ($keyType eq "entryRight") {
						my $newC=$entry; 
						if ($this->{c1Pattern}[1]) {
							$newC=~s/$this->{c1Pattern}[0]/$this->{c1Pattern}[1]/ee;
						}
						$groupedCoocTable->{"\t".$newC}+=$value;
					} elsif ($entry1) {
						my ($newC1,$newC2)=($entry1,$entry2);
						if ($this->{c1Pattern}[1]) {
							$newC1=~s/$this->{c1Pattern}[0]/$this->{c1Pattern}[1]/ee;
							$newC2=~s/$this->{c1Pattern}[0]/$this->{c1Pattern}[1]/ee;
						}

						if ($keyType eq "entry1RelEntry2") {
							$groupedCoocTable->{$newC1."\t".$rel."\t".$newC2}+=$value;
						} else {
							$groupedCoocTable->{$newC1."\t".$newC2}+=$value;
						}
					} elsif ($keyType eq "rel") {
						$groupedCoocTable->{"\t".$newRel."\t"}+=$value;
					} else {
						# nothing to change (rel or tot)
						$groupedCoocTable->{$key}=$value;
					}
				}
			}
			$coocTable=$groupedCoocTable;
			$noDecode=1;
		}
		
		# processing the cooc table (the old or the new one)
		while (my ($key,$value)=each(%{$coocTable})) {
			my ($keyType,$entry1,$entry2,$rel);
			if ($key=~/^([^\t]+)\t([^\t]+)$/) {
				if ($noDecode) {
					$entry1=$1;
					$entry2=$2;
				} else {
					$entry1=decode($this->{fileEncoding},$1);
					$entry2=decode($this->{fileEncoding},$2);
				}
				
				if ($this->{orderSensitive} && ($entry1=~$this->{c1Pattern}[0] && $entry2=~$this->{c2Pattern}[0]) ||
					(!$this->{orderSensitive} && $entry1=~$this->{c1Pattern}[0] && $entry2=~$this->{c2Pattern}[0]) ||
					(!$this->{orderSensitive} && $entry1=~$this->{c2Pattern}[0] && $entry2=~$this->{c1Pattern}[0]) ) {
					$keyType= "entry1Entry2";
				} 
			} elsif ($key=~/^([^\t]+)\t([^\t]+)\t([^\t]+)$/) {
				if ($noDecode) {
					$entry1=$1;
					$rel=$2;
					$entry2=$3;
				} else {
					$entry1=decode($this->{fileEncoding},$1);
					$rel=decode($this->{fileEncoding},$2);
					$entry2=decode($this->{fileEncoding},$3);
				}
	
				if ($rel=~/$this->{relPattern}[0]/ && ($this->{orderSensitive} && ($entry1=~/$this->{c1Pattern}[0]/ && $entry2=~/$this->{c2Pattern}[0]/) ||
					( !$this->{orderSensitive} && $entry1=~/$this->{c1Pattern}[0]/ && $entry2=~/$this->{c1Pattern}[0]/) ||
					( !$this->{orderSensitive} && $entry2=~/$this->{c1Pattern}[0]/ && $entry1=~/$this->{c1Pattern}[0]/))) {
					$keyType= "entry1RelEntry2";
				}
			}
			
			if ($keyType) {
				my $line={};
				$line->{c1}=$entry1;
				$line->{c2}=$entry2;
				
				# reading form or lemma
				$line->{c1}=~/^([^_]+)/;
				my $l1=$1;
				$line->{c2}=~/^([^_]+)/;
				my $l2=$1;
				if (exists($removalList{$l1."\t".$l2})) {
					#~ $this->printTrace("Ignoring collocation : $l1-$l2\n");
				} else {
					my $pos1="";
					my $pos2="";

					if ($line->{c1}=~/_(\w+)/) {
						$pos1=$1;
					}
					
					if ($line->{c2}=~/_(\w+)/) {
						$pos2=$1;
					}
					$line->{pos}=$pos1.'_'.$pos2;
					
					if ($this->{orderSensitive}) {
						$line->{f1}=$coocTable->{toBytes($line->{c1})."\t"};
						$line->{f2}=$coocTable->{"\t".toBytes($line->{c2})};
					} else {
						$line->{f1}=$coocTable->{"\t".toBytes($line->{c1})};
						$line->{f2}=$coocTable->{"\t".toBytes($line->{c2})};
					}
					die "No frenquency for entry1=$entry1 - change the orderSentitive parameter ?" if (! $line->{f1});
					die "No frenquency for entry2=$entry2 - change the orderSentitive parameter ?" if (! $line->{f2});

					$line->{f12}=$value;
					$line->{N}=$coocSpaceSize;
					$line->{matchList}=matchWithCollocationList($line->{c1},$line->{c2});
					if ($keyType eq "entry1RelEntry2") {
						$line->{rel}=$rel;
						$line->{freqRel}=$coocTable->{"\t".toBytes($rel)."\t"};
					}
					$this->computeAM($line);
					if (eval($filteringExpr)) {
						push(@results,$line);
						# recording the data for the reported groups
						if ($groupReport) {
							my $c1Report=$line->{c1};
							my $c2Report=$line->{c2};
							if ($this->{groupBy}[1]) {
								$c1Report=~s/$this->{groupBy}[0]/$this->{groupBy}[1]/ee;
								$c2Report=~s/$this->{groupBy}[0]/$this->{groupBy}[1]/ee;
								if (!exists($groupReportCoocTable{$c1Report."_".$c2Report})) {
									$groupReportCoocTable{$c1Report."_".$c2Report}={};
								}
								$groupReportCoocTable{$c1Report."_".$c2Report}{$line->{c1}."\t".$line->{c2}}+=$value;

							}
						}
					} else {
						my $l=join (", ",map {$_."=>".$line->{$_}} keys(%{$line}));
						$this->printTrace("$l is filtered out\n");
					}
				}
			}
		}
		my @finalResults=sort {orderCoocResult($this->{orderBy})} @results;

		print OUTPUT join("\t", @{$this->{displayColumns}})."\n";
		foreach my $line ( @finalResults ) {
			#~ my $displayLine=join("\t",map {decode($this->{fileEncoding}, $line->{$_})} @{$this->{displayColumns}});
			my $displayLine=join("\t",map {$line->{$_}} @{$this->{displayColumns}});
			print OUTPUT $displayLine."\n";
		}

		# printing output on Group Report if necessary
		if ($groupReport) {
			print GROUPREPORT $this->{groupReportLineId}."\t".$coocSpaceSize;
			foreach my $group (@{$this->{groupReportKeys}}) {
				my ($groupOccs,$groupTypes,$groupRelFreq)=(0,0,0);
				if (exists($groupReportCoocTable{$group})) {
					my @groupTypes=keys %{$groupReportCoocTable{$group}};
					$groupTypes=@groupTypes;
					foreach my $type (@groupTypes) {
						$groupOccs+=$groupReportCoocTable{$group}{$type};
					}
					$groupRelFreq=$groupOccs/$coocSpaceSize;
				}
				print GROUPREPORT "\t$groupOccs\t$groupTypes\t$groupRelFreq";
			}
			print GROUPREPORT "\n";
			close GROUPREPORT;
		}

		dbmClose( \%collocList);
		if ($this->{useDbm}) {
			dbmClose($this->{coocTableHash});
		}
		#~ untie %collocList;
		#~ untie %coocTable;
		close OUTPUT;
	} else {
		$this->printTrace("Unable to create $outputFileName\n",{warn=>1});
		return 0;
	}
	
	$this->restoreParam();
	return $res;
}

# compute loglike, z-score, t-score for ($n1,$n2,$n12,$N) in contingency table
sub computeAM {
	my $this=shift;
	my $line=shift;
	
	if ($line->{f12}*$line->{f1}*$line->{f2}*$line->{N}==0) {
		$this->printTrace("ERROR one these value is null : f1=$line->{f1}, f2=$line->{f2}, f12=$line->{f12}, N=$line->{N}\n",{warn=>1});
		die;
		return 0;
	}
	
	my $ePP=$line->{f1}*$line->{f2}/$line->{N};
	my $ePA=$line->{f1}*($line->{N}-$line->{f2})/$line->{N};
	my $eAP=($line->{N}-$line->{f1})*$line->{f2}/$line->{N};
	my $eAA=($line->{N}-$line->{f1})*($line->{N}-$line->{f2})/$line->{N};
	
	
	my $lPP=$line->{f12}*log2($line->{f12}/$ePP);
	my $lPA=($line->{f1}-$line->{f12}>0)?($line->{f1}-$line->{f12})*log2(($line->{f1}-$line->{f12})/$ePA):0;
	my $lAP=($line->{f2}-$line->{f12}>0)?($line->{f2}-$line->{f12})*log2(($line->{f2}-$line->{f12})/$eAP):0;
	my $lAA=($line->{N}-$line->{f1}-$line->{f2}+$line->{f12}>0)?($line->{N}-$line->{f1}-$line->{f2}+$line->{f12})*log2(($line->{N}-$line->{f1}-$line->{f2}+$line->{f12})/$eAA):0;

	$line->{"log-like"}= 2*($lPP+$lPA+$lAP+$lAA);
	$line->{"t-score"}=($line->{f12}-$ePP)/sqrt($ePP);
	$line->{"z-score"}=($line->{f12}-$ePP)/sqrt($line->{f12});
	$line->{"pmi"}=log2(($line->{f12}*$line->{N})/($line->{f1}*$line->{f2}));
}

sub matchWithCollocationList {
	my $lemma_cat1=shift;
	my $lemma_cat2=shift;
	$lemma_cat1=~s/(_\w).*/$1/;	# truncate the Pos tag. p.ex. text_NN -> text_N
	$lemma_cat2=~s/(_\w).*/$1/;	# truncate the Pos tag. p.ex. text_NN -> text_N
	if (exists($collocList{$lemma_cat1})) {
		if ($collocList{$lemma_cat1}=~/\b\Q$lemma_cat2\E\b/) {
			#~ print $lemma_cat1." <=> ".$lemma_cat2."\n";
			return 1;
		}
	}
	return 0;
}

sub log2 {
	my $n = shift;
	return log($n)/log(2);
}

# order the coocResults : returns the first non null (1 or -1) comparison
sub orderCoocResult {
	my $keys=shift;
	
	foreach my $key (@{$keys}) {
		# string comparison descending
		if ($key=~/^(c1|c2)>$/) {
			if ($b->{$key} cmp $a->{$key}) {
				return $b->{$key} cmp $a->{$key};
			}
		# string comparison ascending
		} elsif ($key=~/^(c1|c2)<?$/) {
			if ($a->{$key} cmp $b->{$key}) {
				return ($a->{$key} cmp $b->{$key});
			}
		# numeric comparison descending
		} elsif ($key=~/(.*)>$/) {
			if ($b->{$1} <=> $a->{$1}) {
				return $b->{$1} <=> $a->{$1};
			}
		# numeric comparison ascending
		} elsif ($key=~/(.*)<$/) {
			if ($a->{$1} <=> $b->{$1}) {
				return  $a->{$1} <=> $b->{$1};
			}
		# numeric comparison ascending
		} else {
			if ($a->{$key} <=> $b->{$key}) {
				return  $a->{$key} <=> $b->{$key};
			}
		} 
	}
	return 0;
}

#*************************************************************************** anaText ()
# Run treetagger on a text and extract various statistics for textual analysis :
# 	- general stats : nb of chars, words, poncts, sentences, paragraphs
#	- vocabulary stats (freq and specificity, computed on a ref corpus) ordered by decreasing frequency 
#	- vocabulary increase 
#	- projection on various reference corpus (5 frequency ranges : 0-20%, 20-40%, 40-60%, 60-80%, 80-100%)
#	- cooccurrencies
#	- repeated segments
# Input : 
#	- the txt file
#	- the various reference vocabulary csv files (in dic/lang/.)
#	- the tagset translation file in json (in dic/lang/tagset.json)
# Outputs : 
#	- a json file with all the stats
#	- a translated ttg file (with simplified tags)

# Parameters :
#	- lang : string - the language
#	- inputFormat : string - (txt|ttg)
#	- outputFormat : string - (json|CSV)
#	- coocSpan : integer - the sliding window full width to compute cooccurrences - 0=nocomputation
#	- repeatedSegmentsMaxLength - indicates the size (in word) of the sliding window for repeatedSegments- 0= nocomputation
#	- catPattern - a category pattern transformation scheme eq [qr/(.*?):.*/,'$1']
#	- useSimplifiedTagset : boolean - indicates if the tagset has to translated into simplified tagset
#	- tagsetName : string - the name of the tagset to translate (default is 'tagsetTreetagger')
#	- labelLanguage : string - the name of the target language for the labels
#	- vocIncreaseStep : integer - every 'step' occurrences, the vocabulary increase is recorded (the vocSize is pushed) - 0=nocomputation
# 	- refCorpus : string	- the filename of a CSV file with lemma tab frequency
#	- refCorpora : {name=>string*} - a list of filenames of various corpora with various frequency ranges 
#	- features2record : {cat=>qr/regex/*}	- a list of features to record in stat, in percentage, for various POS
# 	- global : boolean - if true statistics are computed globally and only one json is created - if false, one json is created for every treetagger file


sub anaText {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($anaTextDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	
	my $res=1;
	
	$this->printTrace("\n########### Executing function anaText()\n");

	# loading the tagset labels dictionary
	if ($this->{features2record}) {
		$this->loadTagsetLabels();
	}

	# reading the reference corpus
	if ($this->{refCorpus}) {
		if (-e $this->{refCorpus} && open(REFCORPUS,"<:utf8",$this->{refCorpus})) {
			$this->printTrace("Reading reference corpus stats in $this->{refCorpus} for specificity computation.\n");
			$this->{refCorpusHash}={};
			$this->{refCorpusSize}=0;
			while (<REFCORPUS>) {
				$_=~s/\x0D?\x0A?$//; # chomp
				my ($lemma,$freq)=split(/\t/,$_);
				$this->{refCorpusHash}{$lemma}+=$freq; # the same lemma may occur on various lines
				$this->{refCorpusSize}+=$freq;
			}
			close(REFCORPUS);
			
		} else {
			$this->printTrace("Warning : unable to read file $this->{refCorpus} !!!\nSpecificity computation will be skipped\n",{warn=>1});
		}
	}

	# Processing paragraphs and running Treetagger
	if ($this->{inputFormat} ne "ttg") {
		my $outputDir=$this->{outputDir};
		my $outputFileName=$this->{outputFileName};
		$this->{outputDir}=$this->{outputDir}."/temp";

		$this->setParam( { 
			outputFileName=>[qr/(.*)$/i,'$1.para'],
			noEmptyPara=>1
		},{overwriteParam=>1});
		$this->addParaTag({overwriteOutput=>1});


		$this->next();
		
		$this->{filePattern}=qr/(.*).para$/;
		$this->{outputFileName}=[qr/(.*).para$/i,'$1.para.ttg'];
		$this->{tokenize}=1;
		
		$this->runTreetagger({overwriteOutput=>0});

		$this->{outputDir}=$outputDir;
		$this->{outputFileName}=[qr/(.*).para.ttg$/i,'$1.csv'],
		$this->{filePattern}=qr/(.*).para.ttg$/,

	}
	
	#~ print $this->{filePattern}." !!!!!!!!!!!\n";
	#  outputDir and outputFileName are reset and the input will take the newly created *.ttg
	$this->setParam( { 
		useDbm=>0,
		countBy=>'lemma_cat',
		orderSensitive=>0,
		toLowerCase=>0,
		catPattern=>[qr/(.*?)(:.*)?$/,'$1'],
		vocIncreaseStep=>100,
		features2record=>{"VER"=>qr/simp|futu|impf|pper|infi|pres|subp|subi/}
	},{overwriteParam=>1});

	
	# case 1 : statistics are computed globally for all the input files 
	if ($this->{global}) {
		
		$res=$res && $this->extractCoocTable();
		
		if ($this->{outputFormat} =~/json/i) {
			my $outputFileName=$this->handleNewFileName($this->{inputDir}."/anatext.json");
			if ($outputFileName eq "0" or $outputFileName eq "-1")  {
				return $outputFileName ;
			}
			$res=$res && $this->printAnatextJson($outputFileName);
		} else {
			my $outputFileName=$this->handleNewFileName($this->{inputDir}."/anatext.csv");
			if ($outputFileName eq "0" or $outputFileName eq "-1")  {
				return $outputFileName ;
			}
			print "calcul de $outputFileName\n";
			$res=$res && $this->printAnatextCsv($outputFileName);
		}

	} else {
		# case 2 : one json file is made for every input file
		$this->{callback}= sub {
			my $fileName=shift;
			my $res=1;
			
			my ($name,$p,$ext) = fileparse($fileName, qr/\.[^.]*/);
			my $svgFilePattern=$this->{filePattern};

			$this->setParam( { 
				filePattern=>qr/$name$ext$/,
			},{overwriteParam=>1});

			$res=$res && $this->extractCoocTable();
			
			# storing the previously saved pattern
			$this->setParam( { 
				filePattern=>$svgFilePattern,
			},{overwriteParam=>1});
			
			
			my $outputFileName=$this->handleNewFileName($fileName);
			if ($outputFileName eq "0" or $outputFileName eq "-1")  {
				return $outputFileName ;
			}
			if ($this->{outputFormat} =~/json/i) {
				$res=$res && $this->printAnatextJson($outputFileName);
			} else {
				$res=$res && $this->printAnatextCsv($outputFileName);
			}
			return $res;
		};
		
		# run !
		$res = $this->process('Cooccurrence table extraction');
	}
	$this->restoreParam();
	return $res;
}

# private function wich print the tables in a json file
sub printAnatextJson {
	my $this=shift;
	my $outputFileName=shift;
	
	my $allStats= {
		globalStats=>$this->{globalStatsHash},
		featuresStats=>{},
		repeatedSegments=>[],
		vocIncrease=>[],
		occFrequencies=>[],
		coocFrequencies=>[],
	};
	
	# featureStats table : a hash with cats as keys and list of pairs [$fea,$freq] as values
	foreach my $cat (keys %{$this->{featuresHash}}) {
		$allStats->{featuresStats}{$cat}=[];
		foreach my $fea (keys %{$this->{featuresHash}{$cat}}) {
			my $label=$fea;
			if (exists($this->{tagsetLabels}{$this->{language}}{$fea})) {
				$label=$this->{tagsetLabels}{$this->{language}}{$fea};
			}
			push (@{$allStats->{featuresStats}{$cat}},[$fea,$label,$this->{featuresHash}{$cat}{$fea}]);
		}
	}
	
	# repeatedSegments table
	foreach my $key (sort {$this->{repeatedSegmentsHash}{$b} <=> $this->{repeatedSegmentsHash}{$a}} keys %{$this->{repeatedSegmentsHash}}) {
		if ($key ne "__docFreq__") {
			my $disp=0;
			if (exists($this->{repeatedSegmentsHash}{'__docFreq__'}{$key})) {
				$disp=keys %{$this->{repeatedSegmentsHash}{'__docFreq__'}{$key}};
			}
			my $val= $this->{repeatedSegmentsHash}{$key};
			my @toks=split(/ /,$key);
			my $n=@toks;
			push (@{$allStats->{repeatedSegments}},[$n,fromBytes($key),fromBytes($val),$disp]);
		}
	}	
	
	# vocIncrease Table
	my $nbOcc=0;
	foreach my $vocSize (@{$this->{vocIncrease}}) {
		push (@{$allStats->{vocIncrease}},[$nbOcc,$vocSize]);
		$nbOcc+=$this->{vocIncreaseStep};
	}
	
	# from coocTableHash, two distinct tables are made : one for occurrence frequence and one for cooccurrence frequency
	foreach my $key (sort {$this->{coocTableHash}{$b} <=> $this->{coocTableHash}{$a}} keys %{$this->{coocTableHash}}) {
		my $val= $this->{coocTableHash}{$key};
		if ($key=~/^([^\t]+)\t([^\t]+)$/) {
			my ($tok1,$tok2)=($1,$2);
			my ($lemma1,$cat1)=split($this->{entrySep},fromBytes($tok1));
			my ($lemma2,$cat2)=split($this->{entrySep},fromBytes($tok2));
			push @{$allStats->{coocFrequencies}},[$lemma1,$cat1,$lemma2,$cat2,$val];
		} elsif ($key!~/^\t/) {
			my ($lemma1,$cat1)=split($this->{entrySep},fromBytes($key));
			my $disp=0;
			if (exists($this->{coocTableHash}{'__docFreq__'}{$key})) {
				$disp=keys %{$this->{coocTableHash}{'__docFreq__'}{$key}};
			}
			if ($this->{refCorpusHash}) {
				# specificity computation
				my %cont;
				$cont{'f12'}=$val;
				$cont{'f1'}=$this->{globalStatsHash}{tokNum};
				$cont{'f2'}=$this->{refCorpusHash}{$lemma1}+$val;
				$cont{'N'}=$this->{refCorpusSize} + $this->{globalStatsHash}{tokNum};
				$this->computeAM(\%cont);
				my $llr=$cont{"log-like"};
				push @{$allStats->{occFrequencies}},[$lemma1,$cat1,$val,$disp,$llr];
			} else {
				push @{$allStats->{occFrequencies}},[$lemma1,$cat1,$val,$disp];
			}
		}
	}
	
	my $json=JSON->new;
	$json->utf8;
	$json->pretty([1]);
	my $jsonText=$json->encode($allStats);
	
	open(OUT,">",$outputFileName); # la var $jsonText est en utf8 codé sur 8 bits
	print OUT $jsonText;
	close(OUT);
	
	return 1;
}

# private function wich print the tables in various CSV files
sub printAnatextCsv {
	my $this=shift;
	my $outputFileName=shift;
	$outputFileName=~/(.*)csv$/;
	my $prefix=$1;
	
	open(OUT,">:utf8",$prefix."stats.csv"); 
	foreach my $key ('tokNum','charNum', 'sentNum', 'paraNum', 'vocSize') {
		my $val=$this->{globalStatsHash}{$key};
		print OUT $key."\t".$val."\n";
	}
	close(OUT);

	# featureStats table : a hash with cats as keys and list of pairs [$fea,$freq] as values
	open(OUT,">:utf8",$prefix."features.csv"); 
	print OUT join("\t","label","cat","fea","freq")."\n";
	foreach my $cat (keys %{$this->{featuresHash}}) {
		foreach my $fea (keys %{$this->{featuresHash}{$cat}}) {
			my $label=$fea;
			if (exists($this->{tagsetLabels}{$this->{language}}{$fea})) {
				$label=$this->{tagsetLabels}{$this->{language}}{$fea};
			}
			print OUT join("\t",$label,$cat,$fea,$this->{featuresHash}{$cat}{$fea})."\n";
		}
	}
	close(OUT);
	
	# repeatedSegments table
	open(OUT,">:utf8",$prefix."repSeg.csv"); 
	print OUT join("\t","size","ngram","freq","disp")."\n";
	foreach my $key (sort {$this->{repeatedSegmentsHash}{$b} <=> $this->{repeatedSegmentsHash}{$a}} keys %{$this->{repeatedSegmentsHash}}) {
		if ($key ne "__docFreq__") {
			my $disp=0;
			if (exists($this->{repeatedSegmentsHash}{'__docFreq__'}{$key})) {
				$disp=keys %{$this->{repeatedSegmentsHash}{'__docFreq__'}{$key}};
			}
			my $val= $this->{repeatedSegmentsHash}{$key};
			my @toks=split(/ /,$key);
			my $n=@toks;
			print OUT join("\t",$n,fromBytes($key),fromBytes($val),$disp)."\n";
		}
	}
	close(OUT);
	
	# vocIncrease Table
	open(OUT,">:utf8",$prefix."vocIncrease.csv"); 
	print OUT join("\t","nbOcc","vocSize")."\n";
	my $nbOcc=0;
	foreach my $vocSize (@{$this->{vocIncrease}}) {
		print OUT $nbOcc."\t".$vocSize."\n";
		$nbOcc+=$this->{vocIncreaseStep};
	}
	close(OUT);
	
	# from coocTableHash, two distinct tables are made : one for occurrence frequence and one for cooccurrence frequency
	open(OUT1,">:utf8",$prefix."occ.csv"); 
	print OUT1 join("\t","lemma1","cat1","freq","disp","llr")."\n";		
	open(OUT2,">:utf8",$prefix."cooc.csv"); 
	print OUT2 join("\t","lemma1","cat1","lemma2","cat2","freq")."\n";
	foreach my $key (sort {$this->{coocTableHash}{$b} <=> $this->{coocTableHash}{$a}} keys %{$this->{coocTableHash}}) {
		my $val= $this->{coocTableHash}{$key};
		if ($key=~/^([^\t]+)\t([^\t]+)$/) {
			my ($tok1,$tok2)=($1,$2);
			my ($lemma1,$cat1)=split($this->{entrySep},fromBytes($tok1));
			my ($lemma2,$cat2)=split($this->{entrySep},fromBytes($tok2));
			print OUT2 join("\t",$lemma1,$cat1,$lemma2,$cat2,$val)."\n";
		} elsif ($key!~/^\t|__docFreq__/)  {
			my ($lemma1,$cat1)=split($this->{entrySep},fromBytes($key));
			my $disp;
			if (exists($this->{coocTableHash}{'__docFreq__'}{$key})) {
				$disp=keys %{$this->{coocTableHash}{'__docFreq__'}{$key}};
			}
			if ($this->{refCorpusHash}) {
				# specificity computation
				my %cont;
				$cont{'f12'}=$val;
				$cont{'f1'}=$this->{globalStatsHash}{tokNum};
				$cont{'f2'}=$this->{refCorpusHash}{$lemma1}+$val;
				$cont{'N'}=$this->{refCorpusSize} + $this->{globalStatsHash}{tokNum};
				
				$this->computeAM(\%cont);
				my $llr=$cont{"log-like"};
				print OUT1 join("\t",$lemma1,$cat1,$val,$disp,$llr)."\n";			
			} else {
				print OUT1 join("\t",$lemma1,$cat1,$val,$disp)."\n";			
			}
		}
	}
	close(OUT1);
	close(OUT2);
	
	return 1;
}

#***************************************************************************************** parallel texts processing

# Alignment 
# parameters
# !!! warning : Alinea cannot handle filesnames with blank spaces...
# - filePattern : filePattern must capture the commonName in $1
# - outputDir : as usual
# - outputFileName : as usual
# - alignFileName : string composed with variable $commonName $l1 $l2 $ext
# - inputDirL1 : string - the L1 directory
# - inputDirL2 : string - the L2 directory
# - languagePattern : /pattern/ - in $1, the language code for a source file
# - languages : list of string- [L1,L2]
# - inputFormat : txt, ttg, ces, xml
# - outputFormat : cesalign,html,tmx,full_tmx,txt,txt12
# - tmxStyleSheet : string

sub runAlineaLite {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($runAlineaLiteDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	

	$this->printTrace("\n########### Executing function runAlineaLite()\n");

	# checking the parameters
	if (exists($this->{inputDirL1})) {
		if (! exists($this->{inputDirL2})) {
			$this->printTrace("Error : the parameter 'inputDirL2' must be set (and must be different from 'inputDirL1')\n",{warn=>1});
			return 0;
		}
		if ($this->{inputDirL1} eq $this->{inputDirL2}) {
			$this->printTrace("Error : the parameter 'inputDirL2' must be different from 'inputDirL1'\n",{warn=>1});
			return 0;
		}
		$this->{inputDir}=$this->{inputDirL1};
		
	} else {
		if (! exists($this->{languagePattern}) or ! exists($this->{languages})) {
			$this->printTrace("Error : when L1 and L2 files are in the same directory, you must precise the 'languages' parameter as well as the 'languagePattern'\n",{warn=>1});
			return 0;
		}
	}
	$this->printTrace("\nlanguages = [$this->{languages}[0],$this->{languages}[1]]\n");

	# setting callback function
	$this->{callback}= sub {
		my $fileName1=shift;
		my $inputDir=dirname($fileName1);
		$fileName1=~$this->{filePattern};
		my $commonName=basename($1);
		my $l1=$this->{languages}[0];
		my $l2=$this->{languages}[1];
		my $ext=$this->{outputFormat};	# used in the alignedFileName scheme	
		my $fileName2;

		if (exists($this->{inputDirL2})) {
			opendir(DIR,$this->{inputDirL2});
			my @fileL2=grep {$_=~$this->{languagePattern}; ($1 eq $this->{languages}[1]) } grep {$_=~/\Q$commonName\E/ } readdir(DIR);
			closedir(DIR);
	
			if (@fileL2 != 1) {
				if (@fileL2) {
					$this->printTrace("\nWarning : for $fileName1, more than one file has been found in directory  $this->{inputDirL2} - check /filePattern/ parameter \n",{warn=>1});
					return 0;
				} else {
					$this->printTrace("\nWarning : for $fileName1, no file has been found in directory  $this->{inputDirL2} - check /filePattern/ parameter \n",{warn=>1});
					$this->printTrace("commonName = $commonName, languagePattern =  $this->{languagePattern}  , $this->{languages}[0] $this->{languages}[1]\n",{warn=>1});
					return 0;
				}
			} else {
				# success
				$fileName2=$this->{inputDirL2}."/".$fileL2[0];
			}
		} else {
			# same directory : using languagePattern to extract language, and looking for languages[0] 
			if ($fileName1=~$this->{languagePattern} && $1 eq $this->{languages}[0]) { 
				opendir(DIR,$inputDir);
				my @fileL2=grep {$_=~$this->{languagePattern}; ($1 eq $this->{languages}[1]) } grep {$_=~/\Q$commonName\E/ } readdir(DIR);
				closedir(DIR);
				if (@fileL2>1) {
					$this->printTrace("\nWarning : for $fileName1 and language $this->{languages}[1], more than one file has been found in directory $inputDir - check /filePattern/ parameter \n",{warn=>1});
					return 0;
				} elsif (@fileL2==0) {
					$this->printTrace("\nWarning : for $fileName1 and language $this->{languages}[1], no file has been found in directory  $inputDir - check /filePattern/ parameter \n",{warn=>1});
					return 0;
				}
				$fileName2=$inputDir."/".$fileL2[0];
				
			} else {
				return 0;
			}
		}

		my $outputFileName=$this->handleNewFileName($fileName1);
		if ($this->{alignFileName}) {
			my $outputDir=$this->computeOutputDir($fileName1);
			$outputFileName=$this->checkNewFileName($outputDir."/".eval('"'.$this->{alignFileName}.'"'));
		} 
		if ($outputFileName eq "0" or $outputFileName eq "-1")  {
			return $outputFileName ;
		}
		
		my $exe="alinea";
		if ($this->{windows}) {
			$exe="alinea.exe";
		}
		
		if ($this->{outputFormat}=~/ces/i) {
			$this->{outputFormat}="cesalign"
		}
		
		my $commandLine="$this->{alineaDir}/$exe \"$fileName1\" \"$fileName2\" --verbose yes --encoding1 $this->{fileEncoding} --encoding2 $this->{fileEncoding} --alinea_dir \"$this->{alineaDir}/\" --format1 $this->{inputFormat} --format2 $this->{inputFormat} --output_file \"$outputFileName\" --output_format $this->{outputFormat} $this->{options} > ".$this->{logDir}."/Alinea.log 2>&1";
		
		if ($this->{windows}) {
			$commandLine=~s/\//\\/g;
		}
		$this->printTrace("\Executing command line : $commandLine\n");
		
		system($commandLine);
		
		# adding the xsl link to tmx if needed
		if ($this->{outputFormat} eq "tmx" && $this->{tmxStyleSheet}) {
			$this->printTrace("Adding xsl to $outputFileName\n");
						
			open(F,$outputFileName);
			my $content=join("",<F>);
			close(F);
			$content=~s/\xef\xbb\xbf//; # remove BOM
			$content=~s/<.xml version="1.0" encoding="utf-?8"\s*.>/<?xml version="1.0" encoding="utf-8" ?>\n<?xml-stylesheet href="$this->{tmxStyleSheet}" type="text\/xsl"?>/;
			
			open (F,">",$outputFileName);
			print F $content;
			close(F);
		}
		
		return 1;
	};
		
	# run !
	my $res = $this->process('Aligning files');

	$this->restoreParam();
	return $res;
}

# Alignment using Yasa

# parameters
# - yasaDir : the path to yasa exe
# - filePattern : filePattern must capture the commonName in $1
# - outputFileName : as usual
# - alignFileName : string composed with variable $commonName $l1 $l2 $ext - if defined outputFileName not used
# - outputDir : as usual
# - inputDir : contains the L1 files (all files are aligned with the L1 file
# - monoInputDirs : hash - $language=>string - the dirs of source files for each language. If not set, inputDir is taken instead
# - languagePattern : /pattern/ - in $1, the language code for a source file
# - languages : list of string- [L1,L2] # mandatory
# - inputFormat : arcade (yasa format), ces, txt - NB : encoding MUST be UTF8
# - splitSent : boolean - if true, then create segmented file
# - outputFormats : list of string e.g. ["ces", "arc", "rali", "txt", "txt2", "tmx"]
# - printScore : boolean - default 1
# - radiusAroundAnchor : interger - default 30
# - tmxStyleSheet : string

sub runYasa {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($runYasaDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	

	$this->printTrace("\n########### Executing function runYasa()\n");

	# checking the parameters
	if (exists($this->{inputDirL1})) {
		if (! exists($this->{inputDirL2})) {
			$this->printTrace("Error : the parameter 'inputDirL2' must be set (and must be different from 'inputDirL1')\n",{warn=>1});
			return 0;
		}
		if ($this->{inputDirL1} eq $this->{inputDirL2}) {
			$this->printTrace("Error : the parameter 'inputDirL2' must be different from 'inputDirL1'\n",{warn=>1});
			return 0;
		}
		$this->{inputDir}=$this->{inputDirL1};
		
	} else {
		if (! exists($this->{languagePattern}) or ! exists($this->{languages})) {
			$this->printTrace("Error : when L1 and L2 files are in the same directory, you must precise the 'languages' parameter as well as the 'languagePattern'\n",{warn=>1});
			return 0;
		}
	}

	# setting callback function
	$this->{callback}= sub {
		my $fileName1=shift;
		my $inputDir=dirname($fileName1);
		my $inputDir2;
		$fileName1=~$this->{filePattern};
		my $commonName=basename($1);
		my $l1=$this->{languages}[0];
		my $ext="ces"; # in a first step, output from Yasa is in CES format. Then the other output format are generated
		my @l2=@{$this->{languages}};
		shift @l2; # $l1 is deleted from @l2
		my $fileName2;
		my @fileL2;

		if (exists($this->{monoInputDirs})) {
			foreach my $lang (@l2) {
				my $inputDir2;
				if (exists($this->{monoInputDirs}{$lang})) {
					$inputDir2=$this->{monoInputDirs}{$lang};
				} else {
					$inputDir2=$this->{inputDir};
					$this->{monoInputDirs}{$lang}=$inputDir2;
				}
				opendir(DIR,$inputDir2);
				my @files=grep {$_=~$this->{languagePattern}; $1 eq $lang } grep {$_=~/\Q$commonName\E/ } readdir(DIR);
				closedir(DIR);
		
				if (@files ==0) {
					$this->printTrace("\nWarning : for $fileName1 and language $lang no file has been found in directory  $inputDir2 - check /filePattern/ parameter \n",{warn=>1});
					return 0;	
				} elsif (@files >1) {
					$this->printTrace("\nWarning : for $fileName1 and language $lang more than one file has been found in directory  $inputDir2 (@files) - check /filePattern/ parameter \n",{warn=>1});
					return 0;
				}
				push(@fileL2,$inputDir2."/".$files[0]);
			}
		} else {
			# same directory : using languagePattern to extract language, and looking for languages[0] 
			if ($fileName1=~$this->{languagePattern} && $1 eq $l1) { 
				$inputDir2=$inputDir;
				opendir(DIR,$inputDir);
				@fileL2=map { $inputDir2."/".$_} grep { $_=~$this->{filePattern} && $1 eq $commonName && $_=~$this->{languagePattern} && inArray($1,@l2) } readdir(DIR);
				closedir(DIR);
				#~ if (@fileL2>1) {
					#~ $this->printTrace("\nWarning : for $fileName1 and language $this->{languages}[1], more than one file has been found in directory $inputDir - check /inputPattern/ parameter [@fileL2] \n",{warn=>1});
					#~ return 0;
				#~ } els
				if (@fileL2==0) {
					$this->printTrace("\nWarning : for $fileName1 and language $this->{languages}[1], no file has been found in directory  $inputDir - check /inputPattern/ parameter \n",{warn=>1});
					return 0;
				}
			} else {
				return 0;
			}
		}
		
		# yasa will produce ces format. Then all format will be converted to get all the output formats
		my $outputFormat="c";
		if ($this->{printScore}) {
			$outputFormat.="s";
		}	
				
		my $inputFormat;

		if ($this->{inputFormat}  eq "txt") {
			$inputFormat="o";
			if ($this->{splitSent}) {
				# creating segmented file
				$this->saveParam();
				$this->{outputDir}=$inputDir."/seg";
				delete($this->{outputDirPattern});
				$this->{filePattern}=basename($fileName1).'$';
				$this->{outputFileName}=[qr/[.]\w+$/,".txt"];
				$this->{language}=$this->{languages}[0];
				$this->splitSentences({overwriteOutput=>1});
				$fileName1=~s/([^\/]+)[.]\w+$/seg\/$1.txt/;
				$this->restoreParam();
				$fileName1=$inputDir."/seg/".basename($fileName1);
			}
		} else {
		# handling other formats and creating arc files
			$inputFormat="a";
			my $source=$this->readSource($fileName1,$this->{languages}[0]);
			my $arcDir=$inputDir."/seg";
			if (! -d $arcDir) {
				mkdir $arcDir;
			}
			my $arcFileName=$arcDir."/".basename($fileName1);
			open(OUT,">:utf8",$arcFileName);
			print OUT "\n<text>\n<divid='d1'>\n<pid='d1p1'>\n";
			my $num=0;
			foreach my $sent (@{$source->{sents}}) {
				my $s=$sent;
				$s=~s/(.*)\t.*\t.*/$1/g;
				my $id=$source->{num2IdSent}[$num];
				print OUT "<s id=\"$id\">\n";
				print OUT $s."\n";
				print OUT "</s>\n";
				$num++;
			}
			print OUT "</p>\n</div>\n</text>\n";
			close(OUT);
			$fileName1=$arcFileName;			
		}
		my $app="yasa";
		if ($this->{yasaDir}) {
			$app=$this->{yasaDir}."/yasa";
		}

		# we have to records in this array all the outputFileNames, in order to merge them later;
		my @outputFileNames;
		foreach my $fileName2 (@fileL2) {
			my $inputDirL2=dirname($fileName2);
			$fileName2=~$this->{languagePattern};
			my $l2=$1;
			# compute the outputFileName, on the base of $fileName1
			my $outputFileName=$this->handleNewFileName($fileName1);
			if ($this->{alignFileName}) {
				my $outputDir=$this->computeOutputDir($fileName1);
				$outputFileName=$this->checkNewFileName($outputDir."/".eval('"'.$this->{alignFileName}.'"'));
			}
			if ($outputFileName eq "0" or $outputFileName eq "-1")  {
				return $outputFileName ;
			}
			#~ $outputFileName.=".ces";
			$this->printTrace("\nProcessing files ($fileName1,$fileName2) to get $outputFileName\n");
		
			if ($this->{inputFormat}  eq "txt") {
				if ($this->{splitSent}) {
					$this->saveParam();
					$this->{outputDir}=$inputDirL2."/seg";
					delete($this->{outputDirPattern});
					$this->{outputFileName}=[qr/$/,""];
					$this->{filePattern}=basename($fileName2).'$';
					$this->{language}=$l2;			
					$this->splitSentences({overwriteOutput=>1});
					$this->restoreParam();
					$fileName2=$inputDirL2."/seg/".basename($fileName2);
				}
			} else {
				my $source=$this->readSource($fileName2,$l2);
				my $arcDir=$inputDirL2."/seg";
				if (! -d $arcDir) {
					mkdir $arcDir;
				}
				my $arcFileName=$arcDir."/".basename($fileName2);
				open(OUT,">:utf8",$arcFileName);
				print OUT "\n<text>\n<divid='d1'>\n<pid='d1p1'>\n";
				my $num=0;
				foreach my $sent (@{$source->{sents}}) {
					my $id=$source->{num2IdSent}[$num];
					my $s=$sent;
					$s=~s/(.*)\t.*\t.*/$1/g;
					print OUT "<s id=\"$id\">\n";
					print OUT $s."\n";
					print OUT "</s>\n";
					$num++;
				}
				print OUT "</p>\n</div>\n</text>\n";
				close(OUT);
				$fileName2=$arcFileName;
			}

			
			my $commandLine= "$app -i $inputFormat -o $outputFormat -b $this->{radiusAroundAnchor}  \"$fileName1\" \"$fileName2\" \"$outputFileName\" > ".$this->{logDir}."/yasa.log 2>&1";
		
			if ($this->{windows}) {
				$commandLine=~s/\//\\/g;
			}
			$this->printTrace("\nExecuting command line : $commandLine\n");

			system($commandLine);
			push(@outputFileNames,basename($outputFileName));
		}

		# if more than two languages, we have to merge the pairs
		if (@l2>1) {
			foreach my $outputFormat (@{$this->{outputFormats}}) {
				$this->saveParam();
				$this->{outputFormat}=$outputFormat;
				$this->{monoInputFormat}=$this->{inputFormat};
				$this->{inputFormat}="ces";
				$this->{commonNamePattern}=qr/(\Q$commonName\E)/;
				# monoInputDir must be set because it will be different of inputDir (which contains the alignment file)
				foreach my $lang ($l1,@l2) {
					if (!exists($this->{monoInputDirs}{$lang})) {
						$this->{monoInputDirs}{$lang}=$this->{inputDir};
					}
				}	
				$this->{inputDir}=$this->{outputDir};
				my $pat="(".join("|", @outputFileNames).")";
				$this->{outputFileName}=[qr/.ces$/,".$outputFormat"];
				$this->{filePattern}=qr/$pat/;
				$this->{languagePattern}=qr/((\w\w-)?\w\w)[.]\w+$/;
				$this->mergeParaCorp();
				$this->restoreParam();
			}
		} else {
			foreach my $outputFormat (@{$this->{outputFormats}}) {
				$this->saveParam();
				if ($outputFormat !~/^ces/i) {
				# creation of tmx/txt file if required
					$this->saveParam();
					$this->{commonNamePattern}=qr/\Q$commonName\E/;
					$this->{inputFormat} = $this->{monoInputFormat};
					
					# monoInputDir must be set because it will be different of inputDir (which contains the alignment file)
					foreach my $lang ($l1,@l2) {
						if (!exists($this->{monoInputDirs}{$lang})) {
							$this->{monoInputDirs}{$lang}=$this->{inputDir};
						}
					}	
					$this->{inputDir}=$this->{outputDir};
					#~ my $pat=join("|",map { '\Q'.$_.'\E'} @outputFileNames); # !!! ne marche pas avec \Q \E !!!!
					my $pat=join("|",@outputFileNames);
					$this->{filePattern}=qr/$pat/;
					$this->{inputFormat}="ces";
					$this->{idSentPrefix}="";
					$this->{supprPeriod}=1;
					$this->{outputFileName}=[qr/.ces$/,".$outputFormat"];
					$this->printTrace("inputDir= $this->{inputDir}, filePattern= $this->{filePattern}, commonName=$commonName\n");
					$this->convertParaCorp();
					$this->restoreParam();
				}
			}
		}

		return 1;
	};
		
	# run !
	my $res = $this->process('Aligning files');

	$this->restoreParam();
	return $res;
}

# Alignment using JAM

# parameters

# - filePattern : filePattern must capture the commonName in $1
# - inputDir : as usual
# - outputFileName : as usual
# - outputDir : as usual
# - fileEncoding : as usual
# - languagePattern : /pattern/ - in $1, the language code for a source file
# - languages : optional list of string- [L1,L2,L3...]
# - inputFormat : ces, txt (one sentence per line) 
# - outputFormat : ces, txt, tmx, csv 
# - options : string - concatenation of any option below
#		--anchorPointFile CSVFILE	: load some anchor points to initialize aligning process
#		--anchorPointMarkup 		: anchor points markup for hard segmentation
#		--finalCompletion			: use the Gale & Church algorithme to finally complete aligning process
#		--printPairwiseAlignment	: print all the alignments two by two
#		--printMergedAlignment		: print all the pairwise alignments merged into a single file
#		--lexicon					: name of the file containing a multilingual lexicon
# - tmxStyleSheet : string


sub runJAM {
	my $this=shift;
	my $options=shift;
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($runJamDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	

	$this->printTrace("\n########### Executing function runJAM()\n");

	# checking the parameters
	if (! exists($this->{languagePattern})) {
		$this->printTrace("Error : you must indicate the 'languagePattern' pattern\n",{warn=>1});
		return 0;
	}

	my %processedCommonName; # one common name may be processed only once
	
	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		my $inputDir=dirname($fileName);
		$fileName=~$this->{filePattern};
		my $commonName=basename($1);
		my @files;
		
		
		# only process files corresponding to first language
		if (! exists($processedCommonName{$commonName}) && $fileName=~$this->{languagePattern}) {
			$processedCommonName{$commonName}=1;
			# same directory : using $commonName to group all files

			opendir(DIR,$inputDir);
			my @f=readdir(DIR);
			if (exists($this->{languages}) && @{$this->{languages}}>0 ) {
				$this->printTrace("\n$this->{languages}\n",{warn=>1});
				# in this case, selecting files in the same order than @languages
				my @namedFiles=grep { $_=~$this->{filePattern} && $_=~/\Q$commonName\E/ }  @f;
				foreach my $lang (@{$this->{languages}}) {
					my @oneFile=grep { $_=~$this->{languagePattern} && $1 eq $lang} @namedFiles;
					if (@oneFile==0) {
						$this->printTrace("\nWarning : for commonName=($commonName) and language=$lang, no file has been found in directory $inputDir - check filePattern=/$this->{filePattern}/ and languagePattern=/$this->{languagePattern}/ parameter \n",{warn=>1});
						return 0;
					}
					push(@files,$oneFile[0]);
				}

			} else {
				@files=sort grep { $_=~$this->{filePattern} && $_=~$this->{languagePattern} && $_=~/\Q$commonName\E/ }  @f;
			}
			closedir(DIR);
			if (@files==0) {
				$this->printTrace("\nWarning : for commonName=($commonName), no file has been found in directory $inputDir - check filePattern=/$this->{filePattern}/ and languagePattern=/$this->{languagePattern}/ parameter \n",{warn=>1});
				return 0;
			} elsif (@files==1) {
				$this->printTrace("\nWarning : for commonName=($commonName), only one file has been found in directory $inputDir - check filePattern=/$this->{filePattern}/ and languagePattern=/$this->{languagePattern}/ parameter \n",{warn=>1});
				return 0;
			}

			$this->printTrace("\nProcessing files (@files)\n");
			
			
			# creating segmented file
			if ($this->{inputFormat}  eq "txt" && $this->{splitSent}) {

				foreach my $file (@files) {
					$file=~/$this->{languagePattern}/;
					my $lang=$1;
					$this->saveParam();
					$this->{outputDir}=$inputDir."/seg";
					$this->{filePattern}=qr/\Q$file\E$/;
					$this->{outputFileName}=[qr/[.]\w+$/,'.txt'];
					$this->{language}=$lang;
					$this->splitSentences({overwriteOutput=>1});
					$this->restoreParam();
				}
				@files=map { my $file=$_; $file=~s/([^\/]+)[.]\w+$/seg\/$1.txt/ ; $file } @files;
			}

			my @languages=map { $_=~$this->{languagePattern};$1 } @files;
			my $outputDir=$this->computeOutputDir($fileName);
			my $outputFileName=$outputDir."/".$commonName.".".join("-",@languages).".".$this->{outputFormat};

			$outputFileName=$this->checkNewFileName($outputFileName);

			if ($outputFileName eq "0" or $outputFileName eq "-1")  {
				return $outputFileName ;
			}
			
			my $commandLine= "perl $this->{jamDir}/JAM.pl ".join(" ",map {"\"$inputDir/$_\""} @files)." --inputFormat $this->{inputFormat} --outputPath  $outputDir --outputFormat $this->{outputFormat} --encoding $this->{fileEncoding} --verbose $this->{verbose} --logDir $this->{logDir} $this->{options}";
			

			if ($this->{windows}) {
				$commandLine=~s/\//\\/g;
			}
			$this->printTrace("\nExecuting command line : $commandLine\n");

			system($commandLine);
			
			return 1;
		}
		return 1;
	};
		
	# run !
	my $res = $this->process('Aligning files');

	$this->restoreParam();
	return $res;
}

# note : filePattern MUST match the common name in $1 group
sub runLFAligner {
	my $this=shift;
	my $options=shift;
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($runLFADefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	

	$this->printTrace("\n########### Executing function runLFAligner()\n");

	# checking the parameters
	if (! exists($this->{languagePattern})) {
		$this->printTrace("Error : you must indicate the 'languagePattern' pattern\n",{warn=>1});
		return 0;
	}

	my %processedCommonName; # one common name may be processed only once
	
	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		my $inputDir=dirname($fileName);
		$fileName=~$this->{filePattern};
		my $commonName=basename($1);
		my @files;
		
		
		# only process files corresponding to first language
		if (! exists($processedCommonName{$commonName}) && $fileName=~$this->{languagePattern}) {
			$processedCommonName{$commonName}=1;
			# same directory : using $commonName to group all files

			opendir(DIR,$inputDir);
			my @f=readdir(DIR);
			if (exists($this->{languages}) && @{$this->{languages}}>0 ) {
				#~ $this->printTrace("\n$this->{languages}\n",{warn=>1});
				# in this case, selecting files in the same order than @languages
				my @namedFiles=grep { $_=~$this->{filePattern} && $_=~/\Q$commonName\E/ }  @f;
				foreach my $lang (@{$this->{languages}}) {
					my @oneFile=grep { $_=~$this->{languagePattern} && $1 eq $lang} @namedFiles;
					if (@oneFile==0) {
						$this->printTrace("\nWarning : for commonName=($commonName) and language=$lang, no file has been found in directory $inputDir - check filePattern=/$this->{filePattern}/ and languagePattern=/$this->{languagePattern}/ parameter \n",{warn=>1});
						return 0;
					}
					push(@files,$oneFile[0]);
				}
			} else {
				@files=sort grep { $_=~$this->{filePattern} && $_=~$this->{languagePattern} && $_=~/\Q$commonName\E/ }  @f;
			}
			closedir(DIR);
			if (@files==0) {
				$this->printTrace("\nWarning : for commonName=($commonName), no file has been found in directory $inputDir - check filePattern=/$this->{filePattern}/ and languagePattern=/$this->{languagePattern}/ parameter \n",{warn=>1});
				return 0;
			} elsif (@files==1) {
				$this->printTrace("\nWarning : for commonName=($commonName), one one file has been found in directory $inputDir - check filePattern=/$this->{filePattern}/ and languagePattern=/$this->{languagePattern}/ parameter \n",{warn=>1});
				return 0;
			}

			$this->printTrace("\nProcessing files (@files)\n");
			
			
			# creating segmented file
			my $split="y";
			if ($this->{splitSent}==0) {
				$split="n";
			}

			if ($this->{inputFormat}  eq "txt" && $this->{splitSent}) {

				foreach my $file (@files) {
					$file=~/$this->{languagePattern}/;
					my $lang=$1;
					$this->saveParam();
					$this->{outputDir}=$inputDir."/seg";
					$this->{filePattern}=qr/\Q$file\E$/;
					$this->{outputFileName}=[qr/[.]\w+$/,'.txt'];
					$this->{language}=$lang;
					$this->splitSentences({overwriteOutput=>1});
					$this->restoreParam();
				}
				#~ @files=map { my $file=$_; $file=~s/([^\/]+)[.]\w+$/seg\/$1.txt/ ; $file } @files;
				$split="n";
				$inputDir=$inputDir."/seg";
			}

			my @languages=map { $_=~$this->{languagePattern};$1 } @files;
			my $outputDir=$this->computeOutputDir($fileName);
			my $outputFileName=$outputDir."/".$commonName.".".join("-",@languages).".".$this->{outputFormat};

			$outputFileName=$this->checkNewFileName($outputFileName);

			if ($outputFileName eq "0" or $outputFileName eq "-1")  {
				return $outputFileName ;
			}
			

			my $commandLine= "perl $this->{LFADir}/scripts/LF_aligner_3.11_with_modules.pl --filetype t --infiles \"".join(",",map {"$inputDir/$_"} @files)."\" --languages \"".join(",",@languages)."\" --segment $split --tmx y --review n --codes \"".join(",",map { uc($_)} @languages)."\" > ".$this->{logDir}."/LFA.log 2>&1";


			if ($this->{windows}) {
				$commandLine=~s/\//\\/g;
			}
			$this->printTrace("\nExecuting command line : $commandLine\n");

			system($commandLine);
			
			opendir(DIR,$inputDir);
			my @alignDirs=sort grep { /align_\d\d\d\d[.]/ } readdir(DIR);
			closedir(DIR);
			my $lastDir=pop(@alignDirs);
			if ($lastDir) {
				opendir(TMP_DIR,$inputDir."/".$lastDir);
				while (my $f=readdir(TMP_DIR)) {
					if ($f=~/[.]$this->{outputFormat}$/) {
						$this->printTrace("Copying files : $inputDir/$lastDir/$f ->  $outputFileName\n");
						
						open(F,"$inputDir/$lastDir/$f");
						my $content=join("",<F>);
						$content=~s/\xef\xbb\xbf//; # remove BOM
						if ($this->{tmxStyleSheet}) { # add link to TMX
							$content=~s/<.xml version="1.0" encoding="utf-?8"\s+.>/<?xml version="1.0" encoding="utf-8" ?>\n<?xml-stylesheet href="$this->{tmxStyleSheet}" type="text\/xsl"?>/;
						}
						close(F);
						open (F,">",$outputFileName);
						print F $content;
						close(F);
					}
				}
				closedir(TMP_DIR);
			}
			return 1;
		}
		return 1;
	};
		
	# run !
	my $res = $this->process('Aligning files');

	$this->restoreParam();
	return $res;
}


# Format conversion for parallel corpus
# parameters
# - filePattern, inputDir : must be set on alignment file
# - languages : the language list (optional if monoInputDirs is set - for tmx may be ignored)
# - commonNamePattern : /pattern/ - in $1, the name that is shared between alignment file and source files
# - sourceFilePattern : /pattern/ - optional : when a specific pattern is required to filter source files
# - languagePattern : /pattern/ - in $1, the language code for a source file
# - monoInputDirs : hash - $language=>string - the dirs of source files for each language. If not set, inputDir is taken and 'languages' must be set
# - monoOutputDirs : hash - $language=>string - the dirs of target files for each language. If not set, outputDir is taken and 'languages' must be set
# - createMonoFiles : boolean - indicates if monolingual files have to be created (for format : ces, txt, csv)
# - loadTokGrammars : boolean - indicates if language dependent tokenization grammar have to be loaded
# - inputFormat : txt, tmx, ces, xml - format of the alignment file
# - outputFormat : txt, tmx, ces, xml
# - monoInputFormat : string - txt, ces, xml - format of the monolingual files if any
# - tmxStyleSheet : string
# - idSentPrefix : string - default value "s" 
# - supprPeriod : boolean - in ces file, remove thousand separator in sent id, eg. 1,019 becomes 1019

sub convertParaCorp {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($convertParaCorpDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	
	my $inputFormat=$this->{inputFormat};
	my $outputFormat=$this->{outputFormat};
	my $monoInputDirs=$this->{monoInputDirs};
	
	$this->printTrace("\n########### Executing function convertParaCorp()\n");
	
	# checking and setting $this->{languages}
	if (exists($this->{monoInputDirs})) {
		my @languages=sort keys %{$this->{monoInputDirs}};
		if (exists ($this->{languages}) && join(",", @languages) ne join(",",sort @{$this->{languages}})) {
			$this->printTrace("\nError : language list  (".@{$this->{languages}}." is different from dir list (@languages)\n",{warn=>1});
			return 0;
		}
		if (! exists($this->{languages})) {
			$this->{languages}=\@languages;
		}
	}
	
	
	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		my $inputDir=dirname($fileName);
		$this->printTrace("\nProcessing file $fileName\n");

		# extract the language list from the name
		if ( $this->{inputFormat} =~/^(tmx|ces)$/) {
			if (!(exists($this->{languages}) && ref($this->{languages}) eq "ARRAY" && @{$this->{languages}} > 1)) {
				if ($fileName=~/$this->{languagePattern}/) {
					my @langs=split("-",$1);
					$this->{languages}=\@langs;
					$this->printTrace("Language list extracted from file name : @langs\n");
				} else {
					$this->printTrace("The language list has not been defined and the filename is not of the form : name.l1-l2-..-ln.ext\n",{warn=>1});
					return 0;
				}
			}
		}
		
		# check the language list
		if ( ! (exists($this->{languages}) && ref($this->{languages}) eq "ARRAY" && @{$this->{languages}} > 1)) {
			$this->printTrace("\nError : the parameter 'languages' must be set with the language list\n",{warn=>1});
			return 0;
		} else {
			if (exists($this->{languages}) && ref($this->{languages}) eq "ARRAY") {
				$this->printTrace("\nLanguages = (@{$this->{languages}})\n");
			}
		}


		my $commonNamePattern;
		# if commonNamePattern is not set, take file pattern
		if (! exists($this->{commonNamePattern})) {
			my $name=basename($fileName);
			if ($name=~$this->{filePattern} && $1) {
				$commonNamePattern=qr/\Q$1\E/;
			} else {
				$this->printTrace("\nError : the capturing parentheses in fileNamePattern must define a string that is shared by the monolingual files\n",{warn=>1});
				return 0;
			}
		} else {
			$commonNamePattern=$this->{commonNamePattern};
		}

		# if more than one input file is required
		if ($this->{inputFormat} !~/^tmx$|^txt2$/) {
			# initialization of sourceFiles hash
			$this->{sourceFiles}={};
			my $name=basename($fileName);
			if ($name=~ $this->{commonNamePattern}) {
				my $commonName=$1;
				foreach my $lang (@{$this->{languages}}) {
					my $sourceDir=$inputDir;
					if (exists($this->{monoInputDirs}{$lang})) {
						$sourceDir=$this->{monoInputDirs}{$lang};
					}
					opendir(DIR,$sourceDir);
					my @sourceFile;
					if ($this->{sourceFilePattern}) {
						my $pat=$this->{sourceFilePattern};
						@sourceFile=grep { /$pat/} readdir(DIR); # \Q \E already applied
						
					} else {
						@sourceFile=grep {/\Q$commonName\E/} readdir(DIR);
					}
					closedir(DIR);
					
					print @sourceFile."\n";
					if (exists($this->{languagePattern})) {
						#~ @sourceFile=grep {if ($_=~$this->{filePattern} && $_=~$this->{languagePattern}) { $lang eq $1} else { 0 }} @sourceFile;
						print "Recherche dans @sourceFile de la langue $lang extraite avec $this->{languagePattern}\n";
						@sourceFile=grep {if ($_=~$this->{languagePattern}) { $lang eq $1} else { 0 }} @sourceFile;
					}
					if (@sourceFile != 1) {
						if (@sourceFile) {
							$this->printTrace("\nWarning : for $fileName, more than one file has been found for language '$lang' in directory  $this->{monoInputDirs}{$lang} - check /commonNamePattern/ and /languagePattern/ parameters ($this->{sourceFilePattern})\n",{warn=>1});
							$this->printTrace( join("\n",@sourceFile)."\n");
							return 0;
						} else {
							$this->printTrace("\nWarning : for $fileName, no file has been found for language '$lang' in directory $this->{monoInputDirs}{$lang} - check /commonNamePattern/ and /languagePattern/ parameters\n",{warn=>1});
							print $this->{sourceFilePattern}."\n";
							return 0;
						}
					} else {
						# success
						$this->{sourceFiles}{$lang}=$sourceDir."/".$sourceFile[0];
					}
				}

			} else {
				$this->printTrace("\nError : for $fileName, /$this->{commonNamePattern}/ has not been found in dir \n",{warn=>1});
				return 0;
			}
		}
		my $align=$this->readParaCorp($fileName);

		my $outputFileName=$this->handleNewFileName($fileName);
		

		if ($outputFileName eq "0" or $outputFileName eq "-1")  {
			return $outputFileName ;
		} else {
			$this->writeParaCorp($outputFileName,$align);
		}
		return 1;
	};
		
	# run !
	my $res = $this->process('Conversion of alignment files');

	$this->restoreParam();
	return $res;
}

# Merging parallel corpus in a single file
# parameters
# - filePattern, inputDir : must be set on alignment files
# - commonNamePattern : /pattern/ - in $1, the name that is shared between alignment file and source files
# - languagePattern : /pattern/ - in $1, the language code for a source file
# - languages : list - the list of languages
# - monoInputDirs : hash - $language=>string - the dirs of source files for each language. If not set, inputDir is taken and 'languages' must be set
# - monoOutputDirs : hash - $language=>string - the dirs of target files for each language. If not set, outputDir is taken and 'languages' must be set
# - createMonoFiles : boolean - indicates if monolingual files have to be created (for format : ces, txt, csv)
# - inputFormat : txt, ttg, tmx, ces, xml
# - monoInputFormat : string - txt, ces, xml - format of the monolingual files if any
# - tmxStyleSheet : string
# - supprPeriod : boolean - in ces file, suppr thousand separator in sent id, eg. 1,019 becomes 1019


sub mergeParaCorp {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($mergeParaCorpDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	
	my $format=$this->{inputFormat};
	if (!exists($this->{outputFormat})) {
		$this->{outputFormat}=$format;
	}
	# if commonNamePattern is not set, take file pattern
	if (! exists($this->{commonNamePattern})) {
		$this->{commonNamePattern}=$this->{filePattern};
	}

	my $languages=$this->{languages};
	my $commonNamePattern=$this->{commonNamePattern};
	my $LanguagePattern=$this->{LanguagePattern};
	my $monoInputDirs=$this->{monoInputDirs};
	
	
	$this->printTrace("\n########### Executing function mergeParaCorp()\n");

	#~ if (! defined($mergedName)) {
		#~ $this->printTrace("Error : the parameter mergedName is not defined. This parameter is necessary to create the output files  mergedName.l1-l2-ln.ext mergedName.l1.ext mergedName.l2.ext mergedName.ln.ext etc.");
		#~ return -1;
	#~ }
	

	# checking and setting $this->{languages}
	if (exists($this->{monoInputDirs})) {
		my @languages=sort keys %{$this->{monoInputDirs}};
		if (exists ($this->{languages}) && join(",", @languages) ne join(",",sort @{$this->{languages}})) {
			$this->printTrace("\nError : language list  (".@{$this->{languages}}." is different from dir list (@languages)\n",{warn=>1});
			return 0;
		}
		if (! exists($this->{languages})) {
			$this->{languages}=\@languages;
		}
	}
	my $refLanguages=$this->{languages};
	
	if (! exists($this->{languages}) || ref($this->{languages}) ne "ARRAY" || @{$this->{languages}}< 2 ) {
		$this->printTrace("\nError : the parameter 'languages' must be set with the language list\n",{warn=>1});
		return 0;
	} else {
		$this->printTrace("\nLanguages = (@{$this->{languages}})\n");
	}
	
	
	# if more than one input file is required, completing $this->{sourceFiles} hash, used in readParaCorp()
	if ($this->{inputFormat} !~/^tmx$|^txt2$/) {
		if (!exists($this->{commonNamePattern})) {
			$this->printTrace("\nError : the commonNamePattern parameter must be set in order to identify the various source files\n",{warn=>1});
			return 0;
		}
		my $pat=$this->{commonNamePattern};
		# initialization of sourceFiles hash
		$this->{sourceFiles}={};

		foreach my $lang (@{$this->{languages}}) {
			my $sourceDir=$this->{inputDir};
			if (exists($this->{monoInputDirs}{$lang})) {
				$sourceDir=$this->{monoInputDirs}{$lang};
			}
			opendir(DIR,$sourceDir);
			my @sourceFile=grep {/$pat/} readdir(DIR);
			closedir(DIR);
			
			#print "CommonName $commonName SourceFile = @sourceFile\n";
			if (exists($this->{languagePattern})) {
				@sourceFile=grep {if ($_=~$this->{languagePattern}) { $lang eq $1} else { 0 }} @sourceFile;
			}
			if (@sourceFile != 1) {
				if (@sourceFile) {
					$this->printTrace("\nWarning : more than one file has been found for language '$lang' in directory $this->{monoInputDirs}{$lang} - check /commonNamePattern/ and /languagePattern/ parameters\n",{warn=>1});
					return 0;
				} else {
					$this->printTrace("\nWarning : no file has been found for language '$lang' in directory $this->{monoInputDirs}{$lang} - check /commonNamePattern/ and /languagePattern/ parameters\n",{warn=>1});
					return 0;
				}
			} else {
				# success
				$this->{sourceFiles}{$lang}=$sourceDir."/".$sourceFile[0];
			}
		}
	}


	$this->{alignmentHash}={};
	$this->{sources}={};

	# before operating paiwise files, we must forget the full language list
	delete($this->{languages});
	delete($this->{mergedName});
		
	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		
		# setting mergedName
		if (! exists($this->{mergedName})) {
			my $name=basename($fileName);
			$name=~$this->{commonNamePattern};
			$this->{mergedName}=$1;
			$this->printTrace("\nThe common name will be $this->{mergedName}\n");
		} else {
			my $name=basename($fileName);
			$name=~$this->{commonNamePattern};
			if ($1 ne $this->{mergedName}) {
				$this->printTrace("\nFile $fileName does not correspond to the common name $this->{mergedName} : it will be skipped\n");
				return;
			}
		}
		
		$this->printTrace("\nProcessing file $fileName\n");
		
		# extract the language list from the name
		if ( $this->{inputFormat} =~/^(tmx|ces)$/) {
			#~ if (!(exists($this->{languages}) && ref($this->{languages}) eq "ARRAY" && @{$this->{languages}} > 1)) {
				#~ if ($fileName=~/[.]((\w\w-)+\w\w)[.]\w+$/) {
				if ($fileName=~$this->{languagePattern}) {
					my @langs=split("-",$1);
					$this->{languages}=\@langs;
					$this->printTrace("Language list extracted from file name : @langs\n");
				} else {
					$this->printTrace("The language list has not been defined and the filename is not of the form : name.l1-l2-..-ln.ext\n",{warn=>1});
					return 0;
				}
			#~ }
		}
		
		# check the language list
		if ( ! (exists($this->{languages}) && ref($this->{languages}) eq "ARRAY" && @{$this->{languages}} > 1)) {
			$this->printTrace("\nError : the parameter 'languages' must be set with the language list\n",{warn=>1});
			return 0;
		} else {
			if (exists($this->{languages}) && ref($this->{languages}) eq "ARRAY") {
				$this->printTrace("\nLanguages = (@{$this->{languages}})\n");
			}
		}

		# reading the alignment file
		my $align=$this->readParaCorp($fileName);
		# merging alignment with the global structure $this->{alignmentHash}, adding new source into $this->{sources}
		$this->mergeAlign($align);

		return 1;
	};
		
		
	# run !
	my $res = $this->process('Merging of alignment files');

	# now set again the complete language list
	$this->{languages}=$refLanguages;
	my $outputFileName=$this->{outputDir}."/".$this->{mergedName}.".".join("-",@{$this->{languages}}).".".$this->{outputFormat};
	my $check= $this->checkNewFileName($outputFileName);
	if ($check eq "0" or $check == -1) {
		return $check;
	}


	# orderering the links in the new alignment
	my $pivotLanguage=$this->{languages}[0];
	if (exists($this->{pivotLanguage})) {
		$pivotLanguage=$this->{pivotLanguage};
	}
	# initialization of the new alignment
	my $align={};
	$align->{sources}=$this->{sources};
	$align->{alignment}=[];
	my $prevLink;
	foreach my $idSeg(@{$this->{sources}{$pivotLanguage}{num2IdSent}}) {
		my $link=$this->{alignmentHash}{$pivotLanguage}{$idSeg};
		if ($link != $prevLink) {
			
			push(@{$align->{alignment}},$link);
			$prevLink=$link;
		}
	}
	$res=$res && $this->writeParaCorp($outputFileName,$align);
	

	return $res;
	
}

# Function that merges the new links with old ones. For each language, idSeg groups are merged in the new link, and then attached to segId
# through the $this->{alignmentHash}{$lang}{idSeg} hash
sub mergeAlign {
	my $this=shift;
	my $align=shift;
	my $alignment=$align->{alignment};
	my $sources=$align->{sources};
	
	# adding new sources files
	foreach my $lang (keys %{$sources}) {
		if (! exists($this->{sources}{$lang})) {
			$this->{sources}{$lang}=$sources->{$lang};
		}
	}
	
	# merging alignment links in alignmentHash - each idSeg list in link is enriched with new idSegs
	foreach my $link (@{$alignment}) {
		# for each language in the link
		foreach my $lang (keys %{$link}) {
			# for each group of id corresponding to $lang
			my @currentIdSegs=@{$link->{$lang}};
			
			foreach my $idSeg (@currentIdSegs) {
				# if the idSeg is already attached to a previous link
				if (exists($this->{alignmentHash}{$lang}{$idSeg}) && $this->{alignmentHash}{$lang}{$idSeg}!=$link) {
					# all the id groups attached to the old link are adder to $link
					$this->mergeLink($link,$this->{alignmentHash}{$lang}{$idSeg});
				}
				# the current idSeg of $link must be attached to the new link as well
				$this->{alignmentHash}{$lang}{$idSeg}=$link;
			}
		}
	}
}

# add all the id groups of $oldLink to $newLink, for each language (even languages that are not in $newLink)
sub mergeLink {
	my $this=shift;
	my ($newLink,$oldLink)=@_;
	foreach my $lang (keys %{$oldLink}) {
		# adding a new language to $newLink
		if (!exists($newLink->{$lang})) {
			$newLink->{$lang}=[];
		}
		# for each idSeg of the old link, we have to add it to the new link
		foreach my $oldIdSeg (@{$oldLink->{$lang}}) {
			if (! inArray($oldIdSeg,@{$newLink->{$lang}})) {
				my $insertIndex=0;
				# now we have to compute the index to insert $oldIdSeg in the sorted list @{$link->{$lang}
				foreach my $id (@{$newLink->{$lang}}) {
					# sorting order is based on sentence number not id
					if ($this->{sources}{$lang}{indexSents}{$oldIdSeg} < $this->{sources}{$lang}{indexSents}{$id}){
						last;
					}
					$insertIndex++;
				}
				# insert $oldIdSeg
				splice(@{$newLink->{$lang}},$insertIndex,0,$oldIdSeg);
				# now the oldIdSeg must refer to $link
				$this->{alignmentHash}{$lang}{$oldIdSeg}=$newLink;
			}
		}
	}
}

# Evaluation of a aligned corpus by comparing it to a reference
# parameters
# - filePattern, inputDir : must be set on alignment files
# - refFileNamePattern : [/pattern/,string] the transformation scheme that link a file with its reference
# - commonNamePattern : /pattern/ - in $1, the name that is shared between alignment file and source files
# - languagePattern : /pattern/ - in $1, the language code for a source file
# - languages : list - the list of languages
# - monoInputDirs : hash - $language=>string - the dirs of source files for each language. If not set, inputDir is taken and 'languages' must be set
# - monoOutputDirs : hash - $language=>string - the dirs of target files for each language. If not set, outputDir is taken and 'languages' must be set
# - inputFormat : txt, ttg, tmx, ces, xml
# - monoInputFormat : string - txt, ces, xml - format of the monolingual files if any
# - supprPeriod : boolean - in ces file, suppr thousand separator in sent id, eg. 1,019 becomes 1019


sub evalParaCorp {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($evalParaCorpDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});
	
	my $format=$this->{inputFormat};
	if (!exists($this->{outputFormat})) {
		$this->{outputFormat}=$format;
	}
	# if commonNamePattern is not set, take file pattern
	if (! exists($this->{commonNamePattern})) {
		$this->{commonNamePattern}=$this->{filePattern};
	}

	my $languages=$this->{languages};
	my $commonNamePattern=$this->{commonNamePattern};
	my $LanguagePattern=$this->{LanguagePattern};
	my $monoInputDirs=$this->{monoInputDirs};
	
	$this->printTrace("\n########### Executing function evalParaCorp()\n");
	my $outputFileName=$this->handleNewFileName(); # computes the new name and directory, creates the directory and backups previous versions if necessary

	if ($outputFileName eq "0" or $outputFileName eq "-1")  {
		return $outputFileName ;
	}
	open(OUT,">",$outputFileName);


	# checking and setting $this->{languages}
	if (exists($this->{monoInputDirs})) {
		my @languages=sort keys %{$this->{monoInputDirs}};
		if (exists ($this->{languages}) && join(",", @languages) ne join(",",sort @{$this->{languages}})) {
			$this->printTrace("\nError : language list  (".@{$this->{languages}}." is different from dir list (@languages)\n",{warn=>1});
			return 0;
		}
		if (! exists($this->{languages})) {
			$this->{languages}=\@languages;
		}
	}

	
	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		my $inputDir=dirname($fileName);
		$this->printTrace("\nProcessing file $fileName\n");

		# extract the language list from the name
		if ( $this->{inputFormat} =~/^(tmx|ces)$/) {
			if (!(exists($this->{languages}) && ref($this->{languages}) eq "ARRAY" && @{$this->{languages}} > 1)) {
				if ($fileName=~/$this->{languagePattern}/) {
					my @langs=split("-",$1);
					$this->{languages}=\@langs;
					$this->printTrace("Language list extracted from file name : @langs\n");
				} else {
					$this->printTrace("The language list has not been defined and the filename is not of the form : name.l1-l2-..-ln.ext\n",{warn=>1});
					return 0;
				}
			}
		}
		
		# check the language list
		if ( ! (exists($this->{languages}) && ref($this->{languages}) eq "ARRAY" && @{$this->{languages}} > 1)) {
			$this->printTrace("\nError : the parameter 'languages' must be set with the language list\n",{warn=>1});
			return 0;
		} else {
			if (exists($this->{languages}) && ref($this->{languages}) eq "ARRAY") {
				$this->printTrace("\nLanguages = (@{$this->{languages}})\n");
			}
		}

		# if commonNamePattern is not set, take file pattern
		if (! exists($this->{commonNamePattern})) {
			my $name=basename($fileName);
			if ($name=~$this->{filePattern} && $1) {
				$this->{commonNamePattern}=qr/\Q$1\E/;
			} else {
				$this->printTrace("\nError : the capturing parentheses in fileNamePattern must define a string that is shared by the monolingual files\n",{warn=>1});
				return 0;
			}
		}

		# if more than one input file is required
		if ($this->{inputFormat} !~/^tmx$|^txt2$/) {
			# initialization of sourceFiles hash
			$this->{sourceFiles}={};
			my $name=basename($fileName);
			if ($name=~ $this->{commonNamePattern}) {
				my $commonName=$1;
				foreach my $lang (@{$this->{languages}}) {
					my $sourceDir=$inputDir;
					if (exists($this->{monoInputDirs}{$lang})) {
						$sourceDir=$this->{monoInputDirs}{$lang};
					}
					opendir(DIR,$sourceDir);
					my @sourceFile;
					if ($this->{sourceFilePattern}) {
						my $pat=$this->{sourceFilePattern};
						@sourceFile=grep { /$pat/} readdir(DIR); # \Q \E already applied
						
					} else {
						@sourceFile=grep {/\Q$commonName\E/} readdir(DIR);
					}
					closedir(DIR);

					if (exists($this->{languagePattern})) {
						#~ @sourceFile=grep {if ($_=~$this->{filePattern} && $_=~$this->{languagePattern}) { $lang eq $1} else { 0 }} @sourceFile;
						@sourceFile=grep {if ($_=~$this->{languagePattern}) { $lang eq $1} else { 0 }} @sourceFile;
					}
					if (@sourceFile != 1) {
						if (@sourceFile) {
							$this->printTrace("\nWarning : for $fileName, more than one file has been found for language '$lang' in directory  $this->{monoInputDirs}{$lang} - check /commonNamePattern/ and /languagePattern/ parameters ($this->{sourceFilePattern})\n",{warn=>1});
							$this->printTrace( join("\n",@sourceFile)."\n");
							return 0;
						} else {
							$this->printTrace("\nWarning : for $fileName, no file has been found for language '$lang' in directory $this->{monoInputDirs}{$lang} - check /commonNamePattern/ and /languagePattern/ parameters\n",{warn=>1});
							return 0;
						}
					} else {
						# success
						$this->{sourceFiles}{$lang}=$sourceDir."/".$sourceFile[0];
					}
				}

			} else {
				$this->printTrace("\nError : for $fileName, /$this->{commonNamePattern}/ has not been found in dir \n",{warn=>1});
				return 0;
			}
		}
		my $align=$this->readParaCorp($fileName);

		
		my $fileNameRef=$fileName;
		my $replace = '"'.$this->{refFileNamePattern}[1].'"';
		$fileNameRef=~s/$this->{refFileNamePattern}[0]/$replace/ee; # the trick is to evaluate potential $1, $2, etc.
		my $alignRef=$this->readParaCorp($fileNameRef);
		
		# recording the reference alignment in a ref{lang1-num1}{lang2-num2}=lengthSent1*lengthSent2 hash
		my %ref;
		my $fullAlignedSurface=0;
		foreach my $idList ($alignRef->{alignment}) {
			for (my $i=0;$i<@{$this->{languages}}-1;$i++) {
				my $l1=$this->{languages}{$i};
				for (my $j=$i+1;$j<@{$this->{languages}};$j++) {
					my $l2=$this->{languages}{$j};
					my @ids1=@{$idList->{$l1}};
					my @ids2=@{$idList->{$l2}};
					foreach my $id1 (@ids1) {
						my $num1=$align->{sources}{$l1}{indexSents}{$id1};
						my $l1=@{$align->{sources}{$l1}{sents}[$num1]};
						foreach my $id2 (@ids2) {
							my $num2=$align->{sources}{$l1}{indexSents}{$id1};
							my $l2=@{$align->{sources}{$l1}{sents}[$num1]};
							$ref{"$l1-$num1"}{"$l2-$num2"}=$l1*$l2;
							$fullAlignedSurface+=$l1*$l2;
						}
					}
				}
			}
		}
		# computing $surfaceOk and $surfaceWrong
		my $surfaceOk=0;
		my $surfaceWrong=0;
		foreach my $idList ($alignRef->{alignment}) {
			for (my $i=0;$i<@{$this->{languages}}-1;$i++) {
				my $l1=$this->{languages}{$i};
				for (my $j=$i+1;$j<@{$this->{languages}};$j++) {
					my $l2=$this->{languages}{$j};
					my @ids1=@{$idList->{$l1}};
					my @ids2=@{$idList->{$l2}};
					foreach my $id1 (@ids1){
						my $num1=$align->{sources}{$l1}{indexSents}{$id1};
						my $l1=@{$align->{sources}{$l1}{sents}[$num1]};
						foreach my $id2 (@ids2) {
							my $num2=$align->{sources}{$l1}{indexSents}{$id1};
							my $l2=@{$align->{sources}{$l1}{sents}[$num1]};
							if (exists($ref{"$l1-$num1"}{"$l2-$num2"})) {
								$surfaceOk+=$ref{"$l1-$num1"}{"$l2-$num2"};
							} else {
								$surfaceWrong+=$l1*$l2;
							}
						}
					}
				}
			}
		}
		
		# computing P and R
		if ($fullAlignedSurface) {
			my $precision=$surfaceOk/($surfaceWrong+$surfaceOk);
			my $recall=$surfaceOk/$fullAlignedSurface;
			my $F=2*$precision*$recall/($precision+$recall);
			print OUT "$fileName\tP=$precision\tR=$recall\tF=$recall\n";
		} else {
			$this->trace("For $fileName, no alignment found in $fileNameRef\n");
			print OUT "$fileName\tP=N/A\tR=N/A\tF=N/A\n";
		}


		return 1;
	};
		
		
	# run !
	my $res = $this->process('Evaluation of alignment files');
	close(OUT);

	return $res;
	
}



# read alignment and source files if required
# Parameters !
# sourceFiles : hash : lang => fileName
# languages : the language list
# arg2 : the alignment file name
# output : 
# return value : hash - {alignment=>[{lang1=>[id*],lang2=>[id*]}*],sources=>{lang=>{num2IdSent=>[numSent*],indexSents=>{idSent=>numSent*},sents=>[[tokString*]*],tokSeparator=>string}}*}
sub readParaCorp {
	my $this=shift; # pipeline object
	my $alignFile=shift;
	
	my $params=shift;
	
	my $refLanguages=$this->{languages};
	my $format=$this->{inputFormat}; 				# ces, txt, txt2, tmx
	
	# reading $nbLang parameters
	my $nbLang=@{$refLanguages};

	# the result of the function is in following vars 
	my %sources; # hash which contains the sentence arrays for each source language
	
	# initialization of tokenization grammars if required ($refLanguages must be set)
	if ($this->{loadTokGrammars}) {
		$this->{spcTag}=0;		# no space tag
		$this->{printType}=0;	# no type
		$this->{tokSeparator}="\t\t\n"; # cat and lemma fields are empty

		foreach my $lang (@{$refLanguages}) {
			$this->loadTokGrammar($lang);
		}
	}

	

	# if source files has been given
	if (defined($this->{sourceFiles})) {
		
		# processing each source
		foreach my $lang (@{$refLanguages}) {
			# checking if the sourceFile exists
			if (! -f $this->{sourceFiles}{$lang}) {
				$this->printTrace("File ".$this->{sourceFiles}{$lang}." not found (language=$lang).",{warn=>1});
				die;
				return 0;
			}
			$sources{$lang}=$this->readSource( $this->{sourceFiles}{$lang},$lang);
			if (!$sources{$lang}) {
				$this->printTrace("Problem in readParaCorp() : the file format of  ".$this->{sourceFiles}{$lang}." is not valid",{warn=>1});
				return 0;
			}
		}
	}
	
	# main loop : reading the alignment file !!!
	if ($format =~/^ces$/i) {
		# defining event callback for XML reading
		my $startTagCallBack= sub {
			my $elt = shift ; 		# the name of the element
			my $simple = shift ; 	# "/" for a simple element
			my $attr_val = shift ;# hash containing attr=val pairs
			my $refTheText = shift; # last pcdata read
			my $refData= shift; 	# hash containing saved data shared by all functions
			my @languages=@{$refData->{languages}};
			if (lc($elt) eq "link") {
				my $xtargets = $attr_val->{'xtargets'};
				if ($this->{supprPeriod}) {
					$xtargets=~s/,(\d\d\d)/$1/g;
				}
				my @ids=split(/\s*;\s*/,$xtargets.";end");  # $listeID1="123 200 340" (on crée d'abord deux chaînes de caractère:$listeID1, $listeID2)
				pop @ids;
			
				if (@ids != @languages) {
					print STDERR "Declared languages do not match with <link> tag, line $.\ - languages=(@languages) <link xtargets='$xtargets' />\n" ;
					return 0;
				}
				# on teste alors chaque ligne de requête
				my %idList;
				foreach (my $i=0;$i<=$#ids;$i++) {
					my $ln=$languages[$i];
					$idList{$ln}=[split(/ /,$ids[$i])];    # $list{$ln}=["123","200","340"]) (puis on crée des listes à partir des chaînes de caractères)
				}
				push(@{$refData->{alignment}},\%idList);
			}
		};
		my $endTagCallBack=sub {};
		my $pcDataCallBack=sub {};
		my %data;
		$data{alignment}=[];
		$data{languages}=$refLanguages;
		my $res=parseXMLFile($alignFile,$this->{fileEncoding},$startTagCallBack,$endTagCallBack,$pcDataCallBack,\%data);
		if ($res) {
			return {alignment=>$data{alignment},sources=>\%sources};
		} else {
			return 0;
		}
	}
	
	# TMX format : all the data are in one single file
	if ($format =~/tmx/) {
	
		# defining event callback for XML reading
		my $startTagCallBack= sub {
			my $elt = shift ; 		# the name of the element
			my $simple = shift ; 	# "/" for a simple element
			my $attr_val = shift ;# hash containing attr=val pairs
			my $refTheText = shift; # last pcdata read
			my $refData= shift; 	# hash containing saved data shared by all functions
			
			$elt=lc($elt);
			# recording tuid
			if ($elt eq "tu") {
				#~ if (! exists($attr_val->{'tuid'})) {
					#~ $refData->{tuid}++;
				#~ } else {
					#~ $refData->{tuid}=$attr_val->{'tuid'};
				#~ }
				$refData->{tuLanguages}=[];
			}
			# recording segid
			if ($elt eq "seg") {
				my $lang=$refData->{lang};
				if (! exists($attr_val->{'segid'})) {
					$refData->{$lang}{segid}++;
				} else {
					$refData->{$lang}{segid}=$attr_val->{'segid'};
				}
			}

			# recording current language
			if ($elt eq "tuv") {
				$refData->{lang}=$attr_val->{'xml:lang'};
				push(@{$refData->{tuLanguages}},$attr_val->{'xml:lang'});
			}
		};
		my $endTagCallBack=sub {
			my $elt = shift(@_);
			my $refTheText= shift;
			my $refData= shift;
			my $lang=$refData->{lang};
	
			$elt=lc($elt);
			# recording current segment in %sources hash
			if ($elt eq "seg") {
				my $sentence=$$refTheText;
				my $segId=$refData->{$lang}{segid};
				
				my $tokens;
				my $this=$refData->{pipeline};
				$this->{spcTag}=0; # no space tag in the output - tokens are separated by "\n"
				if ($this->{loadTokGrammars}) {
					# parameters for tokenization
					$tokens=$this->stringTokenizer($sentence,$lang);
				} else {
					$tokens=simpleTokenizer($sentence);
				}
				if (! exists($refData->{sources}{$lang})) {
					$refData->{sources}{$lang}{tokSeparator}="";
					$refData->{sources}{$lang}{sents}=[];
					$refData->{sources}{$lang}{indexSents}={};
					$refData->{sources}{$lang}{num2IdSent}=[];
				}
				push(@{$refData->{sources}{$lang}{sents}},$tokens);
				my $num=$#{$refData->{sources}{$lang}{sents}};
				$refData->{sources}{$lang}{indexSents}{$segId}=$num;
				$refData->{sources}{$lang}{num2IdSent}[$num]=$segId;
				if (! exists($refData->{$lang}{idList})) {
					$refData->{$lang}{idList}=[];
				}
				# adding the segment to the current tuple for language $lang
				push (@{$refData->{$lang}{idList}},$segId);
				
			}

			# recording the current translation unit
			if ($elt eq "tu") {
				my %idList;
				foreach my $lang (@{$refData->{tuLanguages}}) {
					# print "for $lang adding tuple : ".join( ",",@{$refData->{$lang}{idList}})."\n";
					$idList{$lang}=$refData->{$lang}{idList};
					$refData->{$lang}{idList}=[];
				}
				push(@{$refData->{alignment}},\%idList);
				delete($refData->{tuLanguages});
			}
		};
		my $pcDataCallBack=sub {};
		
		my %data;
		$data{alignment}=[];
		$data{sources}={};
		$data{segid}=0;
		$data{pipeline}=$this;
		my $res=parseXMLFile($alignFile,$this->{fileEncoding},$startTagCallBack,$endTagCallBack,$pcDataCallBack,\%data);
		
		if ($res) {
			# computing @languages list (if not instanciated)
			if (! exists($this->{languages})) {
				$this->{languages}=[sort keys %{$data{sources}}];
			}
			return {alignment=>$data{alignment},sources=>$data{sources}};
		} else {
			$this->printTrace("Error : $alignFile has a wrong xml format !\n",{warn=>1});
			return 0;
		}
	}
	
	
	# txt format : alignment is implicite
	if ($format =~/^txt$/) {
		my $source0=$sources{$refLanguages->[0]}{sents};
		my $tuNb=@{$source0};
		# step 1 : checking if all sources have the same number of sentences
		for (my $i=1;$i<@{$refLanguages};$i++) {
			if (@{$sources{$refLanguages->[$i]}{sents}} != $tuNb) {
				$this->printTrace("Error : File for language $refLanguages->[$i] and language $refLanguages->[0] do not have the same number of sentences !\n",{warn=>1});
				return 0;
			}
		}
		# step 2 : building the alignment list
		my @alignment;
		for (my $id=1;$id<=@{$source0};$id++) {
			my %idList;
			foreach my $lang (@{$refLanguages}) {
				$idList{$lang}=[$id];
			}
			push(@alignment,\%idList);
		}
		return {alignment=>\@alignment,sources=>\%sources};	
	}
}

# Reading a source file in various format : segmented txt, cesAna, etc. 
# The result is a ref to an array that contains the pairs [id,sent], where $sent is an array of triple [form,cat,lemme] in TTG format 
sub readSource {
	my $this=shift;
	my $sourceFile=shift;
	my $lang=shift; # usefull for tokenization
	my $format=lc($this->{monoInputFormat});
	my $encoding=$this->{fileEncoding};
	
	# in monoInputFormat has not been set, taking the extension
	if (! $format) {
		$this->printTrace("Guessing source file format from the extension.\n");
		$sourceFile=~/[.](\w+)$/;
		$format=$1;
	}
	
	$this->printTrace("Reading file $sourceFile (format=$format)\n");
	# ces format
	if ($format=~/ces/i) {
		# defining event callback for XML reading
		my $startTagCallBack= sub {
			my $elt = shift ; 		# the name of the element
			my $simple = shift ; 	# "/" for a simple element
			my $attr_val = shift ;# hash containing attr=val pairs
			my $refTheText = shift; # last pcdata read
			my $refData= shift; 	# hash containing saved data shared by all functions
			
			$elt=lc($elt);
			if ($elt =~ /^t$|^w$/) {
				delete($refData->{c}); # delete POS
				delete($refData->{l}); # delete LEMMA

				# attr 'pos' or 'cat' or 'c' is taken for 'c' attribute (POS)
				if (exists($attr_val->{pos})) {
					$refData->{c}=$attr_val->{pos};
				} elsif (exists($attr_val->{cat})) {
					$refData->{c}=$attr_val->{cat};
				} elsif (exists($attr_val->{c})) {
					$refData->{c}=$attr_val->{c};
				}
				# attr 'lem' or 'l' or 'lemma' is taken for 'l' attribute 
				if (exists($attr_val->{lem})) {
					$refData->{l}=$attr_val->{lem};
				} elsif (exists($attr_val->{lemma})) {
					$refData->{l}=$attr_val->{lemma};
				} elsif (exists($attr_val->{l})) {
					$refData->{l}=$attr_val->{l};
				}
			}
			if ($elt eq "s") {
				$refData->{currentSent}=[];

				if (exists($attr_val->{id})) {
					$refData->{idSent}=$attr_val->{id};
				} elsif (exists($attr_val->{ID})) {
					$refData->{idSent}=$attr_val->{ID};
				} else {
					$refData->{idSent}++;
				}
			}
		};
		my $endTagCallBack=sub {
			my $elt = shift(@_);
			my $refTheText= shift;
			my $refData= shift;
			my $lang=$refData->{language};
			
			$elt=lc($elt);
			# adding a token [$form,$cat,$lem] to the current table @{$refData->{currentSent}} 
			if ($elt =~ /^t$|^w$/) {
				push(@{$refData->{currentSent}},[$$refTheText,$refData->{c},$refData->{l}]);
			}
			# recording the current pair [idSent,sent] in @{$refData->{sents}} table, where sent is a sentence string in ttg format
			if ($elt =~ /^s$/) {
				my $currentSent;
				# if the sentence is already tokenized
				if (@{$refData->{currentSent}}) {
					$currentSent=join("\n",map { join("\t",@{$_}) } @{$refData->{currentSent}});
				} else {
					# if the text between tag is already tokenized, the separator must be " "
					if ($this->{alreadyTokenized}) {
						$refData->{tokSeparator}=" ";
					} else {
					# in case of internal tokenization, the token separator should be ""
						$refData->{tokSeparator}="";
					}
					# tokenization
					my $sentence=$$refTheText;
					$sentence=~s/^\s+|\s+$//g;
					my $tokens;
					if ($this->{alreadyTokenized}) {
						$currentSent=$sentence;
					} elsif ($this->{loadTokGrammars}) {
						# parameters for tokenization
						$currentSent=$this->stringTokenizer($sentence,$lang);
					} else {
						$currentSent=simpleTokenizer($sentence);
					}
				}
				push(@{$refData->{sents}},$currentSent);
				my $num=$#{$refData->{sents}};
				$refData->{indexSents}{$refData->{idSent}}=$num;
				$refData->{num2IdSent}[$num]=$refData->{idSent};
			}
			
		};
		my $pcDataCallBack=sub {
			my $refTheText= shift;
			my $refData= shift;
		};
		my %data;
		$data{sents}=[];
		$data{indexSents}={};
		$data{num2IdSent}=[];
		$data{idSent}=0;
		$data{language}=$lang;
		$data{tokSeparator}=" ";
		my $res=parseXMLFile($sourceFile,$encoding,$startTagCallBack,$endTagCallBack,$pcDataCallBack,\%data);
		if ($res) {
			die;
			return {indexSents=>$data{indexSents},num2IdSent=>$data{num2IdSent},sents=>$data{sents},tokSeparator=>$data{tokSeparator}};
		} else {
			return 0;
		}
	}
	
		# generic XML format : $refData->{segElement} MUST be set (and optionnaly $refData->{tokElement},$refData->{catAttr},$refData->{lemAttr},$refData->{formAttr})
	if ($format=~/^xml$/i) {
		if (!exists($this->{segElement})) {
			$this->printTrace("Error : Parameter segElement must be defined for generic xml format !\n",{warn=>1});
			return 0;
		}
		# defining event callback for XML reading
		my $startTagCallBack= sub {
			my $elt = shift ; 		# the name of the element
			my $simple = shift ; 	# "/" for a simple element
			my $attr_val = shift ;# hash containing attr=val pairs
			my $refTheText = shift; # last pcdata read
			my $refData= shift; 	# hash containing saved data shared by all functions
			
			if (exists($refData->{tokElement}) && $elt eq $refData->{tokElement}) {
				$refData->{c}=""; # POS
				$refData->{l}=""; # LEMMA
				$refData->{w}=""; # FORM

				# attr 'pos' or 'cat' or 'c' is taken for 'c' attribute (POS)
				if (exists($refData->{catAttr})) {
					$refData->{c}=$attr_val->{$refData->{catAttr}};
				} 
				if (exists($refData->{lemAttr})) {
					$refData->{l}=$attr_val->{$refData->{lemAttr}};
				} 
				if (exists($refData->{formAttr})) {
					$refData->{w}=$attr_val->{$refData->{formAttr}};
				} 
			}
			if (exists($refData->{segElement}) && $elt eq $refData->{segElement}){
				$refData->{currentSent}=[];
				if (exists($attr_val->{id})) {
					$refData->{idSent}=$attr_val->{id};
				} else {
					$refData->{idSent}++;
				}
			}
		};
		my $endTagCallBack=sub {
			my $elt = shift(@_);
			my $refTheText= shift;
			my $refData= shift;
			
			# adding a token [$form,$cat,$lem] to the current table @{$refData->{currentSent}} 
			if (exists($refData->{tokElement}) && $elt eq $refData->{tokElement}) {
				my $w=$$refTheText;
				if ($refData->{w}) {
					$w=$refData->{w};
				}
				push(@{$refData->{currentSent}},[$w,$refData->{c},$refData->{l}]);
			}
			# recording the current pair [idSent,sent] in @{$refData->{sents}} table, where sent is a sentence string in ttg format
			if (exists($refData->{segElement}) && $elt eq $refData->{segElement}) {
				my $currentSent;
				# in case of tokenized sentence
				if (exists($refData->{tokElement}) && @{$refData->{currentSent}}) {
					$currentSent=join("\n",map { join("\t",@{$_}) } @{$refData->{currentSent}});
				} else {
					# tokenization
					my $sentence=$$refTheText;
					$sentence=~s/^\s+|\s+$//g;
					my $tokens;
					if ($this->{alreadyTokenized}) {
						$currentSent=$sentence;
					} elsif ($this->{loadTokGrammars}) {
						# parameters for tokenization
						$currentSent=$this->stringTokenizer($sentence,$lang);
					} else {
						$currentSent=simpleTokenizer($sentence);
					}
				}
				push(@{$refData->{sents}},$currentSent);
				my $num=$#{$refData->{sents}};
				$refData->{indexSents}{$refData->{idSent}}=$num;
				$refData->{num2IdSent}[$num]=$refData->{idSent};
			}
		};
		my $pcDataCallBack=sub {
			my $refTheText= shift;
			my $refData= shift;
		};
		my %data;
		$data{pipeline}=$this;
		$data{sents}=[];
		$data{indexSents}={};
		$data{num2IdSent}=[];
		$data{language}=$lang;
		$data{tokElement}=$this->{tokElement};
		$data{segElement}=$this->{segElement};
		$data{formAttr}=$this->{formAttr};
		$data{lemAttr}=$this->{lemAttr};
		$data{catAttr}=$this->{catAttr};
		$data{tokSeparator}="";
		if ($this->{tokElement} || $this->{alreadyTokenized}) {
			$data{tokSeparator}=" ";
		}
		my $res=parseXMLFile($sourceFile,$encoding,$startTagCallBack,$endTagCallBack,$pcDataCallBack,\%data);
		if ($res) {
			return {indexSents=>$data{indexSents},num2IdSent=>$data{num2IdSent},sents=>$data{sents},tokSeparator=>$data{tokSeparator}};
		} else {
			return 0;
		}
	}
	
	# processing the txt format (aligned segments are simply separated by \n char)
	if ($format =~/^txt(.seg)?$/i) {
		open(IN,"<:encoding($encoding)",$sourceFile);
		my $sents=[];
		my $indexSents={};
		my $num2IdSent=[];
		
		if ($this->{alreadyTokenized}) {
			my $tokens;
			while (<IN>) {
				$_=~s/\x0D?\x0A?$//; # chomp
				# end of sent
				if ($_ eq "") {
					$tokens=~s/^\n//g;
					push(@{$sents},$tokens."\n");
					my $idSent=$this->{idSentPrefix}.($#$sents+1);
					$indexSents->{$idSent}=$#$sents;
					$num2IdSent->[$#$sents]=$idSent;
					$tokens="";
				} else {
					$_=/^([^\t]+)/; # if any tab, the token is the string before
					$tokens+="\n".$1;
				}
			}
		} else {
			while(<IN>) {
				my $tokens;
				
				if ($this->{loadTokGrammars}) {
					# parameters for tokenization
					$tokens=$this->stringTokenizer($_,$lang);
				} else {
					$tokens=simpleTokenizer($_);
				}
				push(@{$sents},$tokens);
				my $idSent=$this->{idSentPrefix}.($#$sents+1);
				$indexSents->{$idSent}=$#$sents;
				$num2IdSent->[$#$sents]=$idSent;
			}
		}
		close(IN);
		return {indexSents=>$indexSents,num2IdSent=>$num2IdSent,sents=>$sents,tokSeparator=>""};
	}
	if ($format =~/^ttg$/i) {
		open(IN,"<:encoding($encoding)",$sourceFile);
		my $sents=[];
		my $indexSents={};
		my $num2IdSent=[];
		my $tokens;

		while (<IN>) {
			$_=~s/\x0D?\x0A?$//; # chomp
			# end of sent
			if ($_ =~/\t$this->{sentMark}\t/) {
				$tokens=~s/^\n//g;
				push(@{$sents},$tokens."\n");
				my $idSent="s".($#$sents+1);
				$indexSents->{$idSent}=$#$sents;
				$num2IdSent->[$#$sents]=$idSent;
				$tokens="";
				
				#~ print $idSent."\n".$sents->[$indexSents->{$idSent}]."\n";
				
			} else {
				$_=/^([^\t]+)/; # if any tab, the token is the string before
				$tokens.="\n".$1;
			}
		}

		close(IN);
		return {indexSents=>$indexSents,num2IdSent=>$num2IdSent,sents=>$sents,tokSeparator=>" "};
	}
	
	
}

# writing an alignment in the output format 
sub writeParaCorp {
	my $this=shift; # pipeline object
	my $fileName=shift;
	my $align=shift;
	
	my $nbLang;
	my $outputFormat=lc($this->{outputFormat});

	# the result of the function is in following vars
	my $alignment=$align->{alignment};
	my $sources=$align->{sources}; # hash which contains the sentence arrays for each source language
	my @languages=keys %{$sources};
	if (exists($this->{languages}) && ref($this->{languages}) eq "ARRAY" ) {
		@languages=@{$this->{languages}};
	}
	
	
	my $OUT;
	my %outputHandles;
	if ($fileName) {
		# for txt2 format, one separate file is created for each language
		if ($outputFormat eq "txt2") {
			foreach my $lang (@languages) {
				my $OUT;
				my $outputFileName=$fileName;
				$outputFileName=~s/(\.\w+$)/.$lang\1/;
				if (open($OUT,">:encoding(".$this->{fileEncoding}.")",$outputFileName)) {
					$this->printTrace("Creating file : $fileName\n");
					$outputHandles{$lang}=$OUT;
				} else {
					$this->printTrace("Error : Unable to create file $fileName\n",{warn=>1});
					return 0;	
				} 
			}
		} else {
		
			if (open($OUT,">:encoding(".$this->{fileEncoding}.")",$fileName)) {
				$this->printTrace("Creating file : $fileName\n");
			} else {
				$this->printTrace("Error : Unable to create file $fileName\n",{warn=>1});
				return 0;
			}
		}
	} elsif (exists($this->{outputHandle})) {
		$OUT=$this->{outputHandle};
	}
	if (! $this->{noHeaderAndFooter}) {
		$this->printHeader($OUT,\@languages,$outputFormat);
	}
	
	# opening monolingual files in write mode
	my %monoFiles;
	if (exists($this->{monoFileHandles})) {
		%monoFiles=%{$this->{monoFileHandles}};
		foreach my $language (@languages) {
			if ($outputFormat eq "ces") {
				# if merging files and "ces" format
				print {$monoFiles{$language}} "	<div doc=\"".$this->{sourceFiles}{$language}."\" >\n";
			}
		}
	} elsif ($this->{createMonoFiles})  {
		foreach my $language (@languages) {
			my $name=basename($fileName);
			# computing name using /commonNamePattern/
			if (exists($this->{commonNamePattern}) && $name=~ $this->{commonNamePattern} && $1) {
				$name=$1.".$language.".$outputFormat;
			} elsif ($name=~/[_.](\w\w(-\w\w)+)[_.]/ && $1=~/$language/) {
				# automatically replacing .l1-l2. scheme by .l1.
				$name=~s/[_.]\w\w(-\w\w)+[_.]/.$language./;
				
			} else {
				$name=$name.".$language.".$outputFormat;
			}
			my $fullName;
			if (exists($this->{monoOutputDirs}{$language})) {
				$fullName=$this->{monoOutputDirs}{$language}."/".$name;
			} else {
				$fullName=$this->{outputDir}."/".$name;
			}
			my $OUT;
			open($monoFiles{$language},">:encoding(".$this->{fileEncoding}.")",$fullName);
			if (! $this->{noHeaderAndFooter}) {
				printMonoHeader($monoFiles{$language},$outputFormat,$this->{fileEncoding});
			}
		}
	}
	
	if ($outputFormat eq "ces") {
		print $OUT "		<linkGrp targType='s'";
		my $i=1;
		foreach my $lang (@{$this->{languages}}) {
			print $OUT " doc$i=\"".$this->{sourceFiles}{$lang}."\"";
			$i++;
		}
		print $OUT ">\n";
	}
	my $tuid=1;
	# printing tuples
	
	foreach my $align (@{$alignment}) {
		my @tuples;
		if ($outputFormat eq "tmx") {
			print $OUT "\t<tu tuid='$tuid'>\n";
			$tuid++;
		}

		foreach my $lang (@languages) {
			if (exists($align->{$lang})) {
				my @ids=@{$align->{$lang}};
				my $sents=join("",map { $sources->{$lang}{sents}[ $sources->{$lang}{indexSents}{$_} ] } @ids);
				if ($outputFormat eq "txt") {
					print $OUT "[$lang:@ids]\t".outputTokens($sents,"txt",$sources->{$lang}{tokSeparator})."\n";
					if (exists($monoFiles{$lang})) {
						print {$monoFiles{$lang}} outputTokens($sents,"txt",$sources->{$lang}{tokSeparator})."\n";
					}
				}
				if ($outputFormat eq "txt2") {
					print {$outputHandles{$lang}} "[@ids]\t".outputTokens($sents,"txt",$sources->{$lang}{tokSeparator})."\n";
					if (exists($monoFiles{$lang})) {
						print {$monoFiles{$lang}} outputTokens($sents,"txt",$sources->{$lang}{tokSeparator})."\n";
					}
				}
				if ($outputFormat eq "tmx") {
					print $OUT "\t\t<tuv id='@ids' xml:lang='$lang'>\n";
					foreach my $id (@ids) {
						print $OUT "\t\t\t<seg>".toXml(outputTokens($sources->{$lang}{sents}[$sources->{$lang}{indexSents}{$id}],"txt",$sources->{$lang}{tokSeparator}))."</seg>\n";
					}
					print $OUT "\t\t</tuv>\n";
					if (exists($monoFiles{$lang})) {
						print {$monoFiles{$lang}} outputTokens($sents,"txt",$sources->{$lang}{tokSeparator})."\n";
					}
				}
				if ($outputFormat eq "csv") {
					print $OUT "[$lang:@ids]".outputTokens($sents,"txt",$sources->{$lang}{tokSeparator})."\t";
					if (exists($monoFiles{$lang})) {
						print {$monoFiles{$lang}} outputTokens($sents,"txt",$sources->{$lang}{tokSeparator})."\n";
					}
				}
				if ($outputFormat eq "ces") {
					# adding "s" to id if necessary
					push (@tuples,join(" ",map {($_=~/^\d+$/)?'s'.$_:$_} @ids));
					if (exists($monoFiles{$lang})) {
						foreach my $id (@ids) {
							print {$monoFiles{$lang}} "\t\t<s id='".(($id=~/^\d+$/)?'s'.$id:$id)."'>\n";
							my $num=$sources->{$lang}{indexSents}{$id};
							#~ print "$num [".$sources->{$lang}{sents}[$num]."]\n";
							print {$monoFiles{$lang}} "\t\t\t".outputTokens($sources->{$lang}{sents}[$sources->{$lang}{indexSents}{$id}],"ces",$sources->{$lang}{tokSeparator})."\n";
							print {$monoFiles{$lang}} "\t\t</s>\n";
						}
					}
				}
			} elsif ($outputFormat eq "csv" && $lang ne $languages[$#languages]) {
				print $OUT "\t";
			} elsif ($outputFormat eq "ces") {
				push (@tuples,"");
			}
			
		}
		if ($outputFormat eq "csv") {
			print $OUT "\n";
		} elsif ($outputFormat eq "ces") {
			print $OUT "			<link xtargets=\"".join(" ; ",@tuples)."\" />\n";
		} elsif ($outputFormat eq "tmx") {
			print $OUT "\t</tu>\n";
		}
	}
	if ($outputFormat eq "ces") {
		print $OUT "		</linkGrp>\n";
	}
	
	foreach my $lang (keys %monoFiles) {
		if (! $this->{noHeaderAndFooter}) {
			# printing footer for monolingual files if necessary
			printMonoFooter($monoFiles{$lang},$outputFormat);
		} elsif ($fileName eq "" && $outputFormat eq "ces") {
			# if merging files and "ces" format
			print {$monoFiles{$lang}} "	</div>\n";
		}
		if (! exists($this->{monoFileHandles})) {
			# closing monolingual files if necessary
			close($monoFiles{$lang});
		}
	}
	
	# printing footer if necessary
	if (! $this->{noHeaderAndFooter}) {
		printFooter($OUT,$outputFormat);
	}
	
	# closing file if necessary
	if ($fileName) {
		close ($OUT);
	}
	$this->printTrace( "writing ".@{$alignment}." tuples - done\n");
	return 1;

}

sub printHeader {
	my $this=shift;
	my $OUT=shift;
	my $languages=shift;
	my $format=shift;
	my $encoding=$this->{fileEncoding};
	
	if (lc($format) eq "tmx") {
		my $xslt="";
		if ($this->{tmxStyleSheet}) {
			$xslt="<?xml-stylesheet href=\"$this->{tmxStyleSheet}\" type=\"text/xsl\"?>\n";
		}
			
		print $OUT qq|<?xml version="1.0" encoding="$encoding"?>
$xslt
<tmx version="1.4">
	<header creationtool="PCPtoolkit" creationtoolversion="Version $VERSION" datatype="PlainText" segtype="sentence" o-encoding="$encoding">
	</header>
	<body>	
|;
	}
	
	if (lc($format) eq "ces") {
		print $OUT qq|<?xml version="1.0" encoding="$encoding"?>
<cesAlign version="1.6">
	<cesHeader version ="2.3">
		<translations>
|;
	foreach my $lang (@{$languages}) {
		print $OUT "\t\t\t<translation>$lang</translation>\n"
	}
	print $OUT qq |		</translations>
	</cesHeader>
|;
	}
}

sub printMonoHeader {
	my $OUT=shift;
	my $format=shift;
	my $encoding=shift;
	if (lc($format) eq "ces") {
		print $OUT qq|<?xml version="1.0" encoding="$encoding"?>
<cesAna version="1.5" type="SENT">
|;	
	}
}

sub printFooter {
	my $OUT=shift;
	my $format=shift;	
	if (lc($format) eq "tmx") {
		print $OUT qq|
	</body>
</tmx>
|;
	}
	
	if (lc($format) eq "ces") {
		print $OUT qq|
</cesAlign>
|;
	}	
}

sub printMonoFooter {
	my $OUT=shift;
	my $format=shift;
		
	if (lc($format) eq "ces") {
		print $OUT qq|
</cesAna>
|;	
	}	
}



#*************************************************************************** computeBleu()
# BLEU score computation
# parameters
# - filePattern, inputDir, outputDir, outputFilePattern : as usual
# - refNumber : integer - the number of ref col to take into account in the TSV file


sub computeBleu {
	my $this=shift;
	my $options=shift;	
	
	# saving the current state of parameters
	$this->saveParam();
	# setting defaultparameters if not already set
	$this->setParam($computeBleuDefaultParam);
	# adding optionnal temporary parameters
	$this->setParam($options,{overwriteParam=>1});	
	
	$this->printTrace("\n########### Executing function computeBleu()\n");
	
	# setting callback function
	$this->{callback}= sub {
		my $fileName=shift;
		my $res=1;
		
		my $outputFileName=$this->handleNewFileName($fileName); # computes the new name and directory, creates the directory and backups previous versions if necessary

		if ($outputFileName eq "0" or $outputFileName eq "-1")  {
			return $outputFileName ;
		}
		$this->printTrace("Compute BLEU score for $fileName (TSV file that include Hypothesis \t ref1 \t ref 2 etc.)\n");

		my $score=bleuScore($fileName,$this->{refNumber});
		if (open(OUT,">:encoding(utf8)",$outputFileName)) {
			print OUT $score;
			close(OUT);
		} else {
			$this->printTrace("Unable to write $outputFileName",{warn=>1});
			return -1;
		}
		return 1;
	};
	
	# run !
	my $res = $this->process('BLEU score computation');
	$this->restoreParam();
	return $res;
}

#------------------------------------------------------------------------------------------------

# private methods

# all the param are saved in the '_saved' properties (including the old value of '_saved' hash : it is a stack !
sub saveParam {
	my $this=shift;
	my %saved;

	while (my ($key,$value)=each %{$this}) {
		$saved{$key}=$value;
	}
	$this->{_saved}=\%saved;
}

# the saved param on the top of the stack are restored !
sub restoreParam {
	my $this=shift;

	# clear new parameters
	foreach my $key (grep {!/_saved/} keys %{$this}) {
		delete($this->{$key});
	}
	
	# restore paramaters
	foreach my $key  (grep {!/_saved/} keys %{$this->{_saved}}) {
		$this->{$key}=$this->{_saved}{$key};
	}
	# poping the old saved parameters
	$this->{_saved}=$this->{_saved}{_saved};
}

sub printParam {
	my $this=shift;
	$this->printTrace("Printing current parameter\n");
	while (my ($key,$value)=each %{$this}) {
		$this->printTrace("$key=>$value\n");
	}
}

# private method that runs the execution of callback function on the files that corresponds to the pattern
# returns 1 if success, 0 if the result is not complete, -1 if an error has occurred
sub process {
	my $this=shift; # the current pipeline
	my $processName=shift;
	my $totFileProcessed=0;
	my $globalResult=1;	
	
	# case 1 : working on a single file !
	if (exists($this->{inputFileName})) {
		$globalResult=$this->{callback}($this->{inputFileName});
		if ($globalResult>0) {
			$totFileProcessed++;
		}
	# case 2 : working on a complete directory
	} else {
		
		my $initDirList=$this->{inputDir};
		
		# if $initDir is a simple scalar then transform it in a list ref with one value only
		if (! ref($initDirList)) {
			$initDirList=[$initDirList];
		}

		foreach my $initDir (@{$initDirList}) {
			my ($result,$nbFileProcessed)=$this->processDir($initDir);
			if ($globalResult!=-1) {
				$globalResult=$globalResult*$result;
			} 
			if ($result==-1) {
				warn "A problem has occurred while processing the $initDir directory\n";
				$globalResult=-1;
			}
			$totFileProcessed+=$nbFileProcessed;
		}
	}
	
	$this->printTrace("\n==> $processName : $totFileProcessed files have been processed !\n");
	return $globalResult;
}

# private method that processes recursively the current directory
# return to value : ($state,$nbOfProcessedFiles)
# note : when a error occurs the function return -1, and the number of processed files is not set, and the state is set to -1
sub processDir {
	my $this=shift; 
	my $currentDir=shift;
	my $DIR;
	my $nbFileProcessed=0;
	
	$this->printTrace("Processing the directory : $currentDir\n");
	
	if (opendir($DIR,$currentDir)) {
		my $res=1;
		my @files=readdir($DIR);
		foreach my $file (@files) {
			if (-d "$currentDir/$file" && $file!~/^\./ && (! -l "$currentDir/$file" || $this->{processLinks}) && $this->{recursion}) {
				my ($r,$nbFileProcessedRec)=$this->processDir("$currentDir/$file");	# recursive call
				if ($r==-1) {
					$res=-1;
				} else {
					$nbFileProcessed+=$nbFileProcessedRec;
				}
			}
			if (-f "$currentDir/$file" && $file=~ $this->{filePattern}) {
			
				# recording the subpatterns of filename in nameHash property
				my %nameHash;
				my $n=1;
				while (eval('defined($'.$n.')')) {
					$nameHash{$n}=eval('$'.$n);
					$n++;
				}
				$this->{nameHash}=\%nameHash;
				
				# run callBack on file !!!
				$this->printTrace("Now processing $currentDir/$file...\n");
				# first, guess encoding
				if ($this->{guessEncoding}) {
					my $beginning;
					open(TEST,"$currentDir/$file");
					read TEST,$beginning,5000;
					close(TEST);
					$this->printTrace("Trying to guess encoding...\n");
					my $charset = detect($beginning);
					if ($charset) {
						$this->{fileEncoding}=$charset;
						$this->printTrace("Encoding $charset has been guessed !!!\n");
					} else {
						$this->{fileEncoding}=$defaultEncodingIfNotGuessed;
						$this->printTrace("Encoding has not been guessed !!! Using default=$this->{fileEncoding}\n");
					}
				}
				my $r=$this->{callback}("$currentDir/$file");
				if ($r>0) {
					$nbFileProcessed++;
				} elsif ($r==-1) {
					$res=-1;
				}
			} else {
				#print "$file DOES NOT MATCH $this->{filePattern}\n";
			}
		}
		closedir($DIR);
		return ($res,$nbFileProcessed);
	} else {
		$this->printTrace("Unable to open the directory : $currentDir\n",{warn=>1});
		return (-1,0);
	}
}

# private method that handle the printing of execution trace on STDOUT and in the log file (and warnings on STDERR)
sub printTrace {
	my $this=shift;
	my $msg=shift;
	my $options={warn=>0};
	if (@_) {
		$options=shift;
	}
	
	if ($this->{verbose}) {
		print STDOUT $msg;
	}
	if ($this->{printLog}) {
		print LOG $msg; 
	}
	if ($options->{warn}) {
		warn $msg;
	}
}


# the new file name is created according the input file name and a replacement scheme
# $fileName includes complete path
# if no $fileName is given, newFileName will be $outputDir."/".basename($this->{outputFileName}->[0]);
sub handleNewFileName {
	my $this=shift;
	my $fileName=shift;
	my $n=shift; # a counter variable used in splitting files
	
	my $newFileName;
	if ($fileName) {
		$newFileName=basename($fileName);
	} 
	my $res=1;
	

	# case of [pattern,replace]
	my $outputDir=$this->computeOutputDir($fileName);
	
	# now outputDir is fixed, only the name will be transformed
	if (defined($this->{outputFileName}[1])) {
		my $replace = '"'.$this->{outputFileName}[1].'"';
		$newFileName=~s/$this->{outputFileName}[0]/$replace/ee; # the trick is to evaluate potential $1, $2, etc.
		$newFileName=$outputDir."/".$newFileName;
		#~ print "$fileName - SEARCH $this->{outputFileName}[0] REPLACE eval($replace) ----> $newFileName\n";	
	} else {
	# case of simple string
		if (ref(\$this->{outputFileName}) eq "SCALAR") {
			$newFileName=$outputDir."/".basename($this->{outputFileName});
		} else {
			$newFileName=$outputDir."/".basename($this->{outputFileName}->[0]);
		}
	}
	# if input file equal output file and $this->{overwriteInput}==0, abort
	if ($newFileName eq $fileName && ! $this->{overwriteInput}) {
		$this->printTrace("the input file $fileName cannot be overwritten overwriteInput=0\n");
		return 0;
	}
	return $this->checkNewFileName($newFileName);
}

# private method that prepares the creation of a new file : creates the directory and backups previous versions if necessary
sub checkNewFileName {
	my $this=shift;
	my $newFileName=shift;
	
	# creating file directory
	if ($this->createDir($newFileName)==-1) {
		my $dir=dirname ($newFileName);
		$this->printTrace("Error : the directory $dir cannot be created\n");
		return -1;
	}
	
	# handling old output file backup
	return $this->ifFileExistBackupOrAbort($newFileName);
}

# apply outputDirPattern on source filename if necessary
sub computeOutputDir {
	my $this=shift;
	my $fileName=shift;
	
	my $outputDir=$this->{outputDir};
	
	# outputDirPattern expresses how to transform the actual dir of $fileName in a new outputDir.
	# Useful to transform dir during recursion
	if (exists($this->{outputDirPattern}) && $this->{outputDirPattern}) {
		$outputDir=dirname($fileName);
		if (defined($this->{outputDirPattern}[1])) {
			my $replace = '"'.$this->{outputDirPattern}[1].'"';
			$outputDir=~s/$this->{outputDirPattern}[0]/$replace/ee;
		} else {
			$this->printTrace("ERROR : the outout dir pattern must follow the form [qr/pattern/,replace]\n");
			return 0;
		}
	}
	return $outputDir;
}

# private method that prepares the creation of a new file : creates the directory and backups previous versions if necessary
sub createDir {
	my $this=shift;
	my $fileName=shift;
	my $dirname  = dirname($fileName);
	if (-f $dirname) {
		$this->printTrace("$dirname already exists as a file and cannot be used as a directory. Aborting operation for $fileName.\n",{warn=>1});
		return -1;
	}
	if (! -e $dirname) {
		$this->printTrace("Creating directory $dirname\n");
		my $res=make_path($dirname);
		if (! $res) {
			$this->printTrace("A problem occurs while creating $dirname\n",{warn=>1});
			return -1;
		}
	}
	return 1;
}

# private function handling backup of old output files
sub ifFileExistBackupOrAbort {
	my $this=shift;
	my $newFileName=shift;

	if (-f $newFileName && $this->{overwriteOutput} && $this->{outputBackupExtension} ne "no") {
		my $i=1;
		if ($this->{outputBackupExtension} eq "bak") {
			$i="";
		} elsif ($this->{outputBackupExtension} eq "bakN") {
			while (-f "$newFileName.bak$i") {
				$i++;
			}
		}
		rename($newFileName,"$newFileName.bak$i");
		$this->printTrace("File $newFileName already exists. The old file is saved as $newFileName.bak$i.\n");
	# if no overwrite, then operation is aborted
	} elsif ( -f $newFileName && ! $this->{overwriteOutput}) {
		$this->printTrace("File $newFileName already exists. Operation is skipped\n");
		return 0;
	}
	return $newFileName;
}


# private static function that removes HTML tags and special encoding in a string
sub strHtml2txt {
	my $text = shift(@_);
	my $deleteTags=shift(@_);
	my $blockTags=shift(@_);

	# suppression des retours chariots

	$text=~s/\n//g;

	# suppression des commentaires
	$text=~s/<!--.*?-->//sg;

	# suppression des sections CDATA
	$text=~s/<![CDATA[.*?]]>//sg;

	# cas 1 : élimination des balises à contenu

	foreach my $deleteTag (@{$deleteTags}) {
		$text=~s/<$deleteTag.*?<\/$deleteTag>//sg;
	}

	# cas 2 : remplacement des balises de block

	foreach my $blockTag (@{$blockTags}) {
		$text=~s/<\/$blockTag>|<$blockTag\/>/\n/sg;
	}

	#  cas 3 : élimination des balises restantes
	$text =~s/<[^>]*>//sg;

	# transformation des entités
	$text=convertEntities($text,0);

	return $text;
}

#************************************************* private functions for tokenization

#  loading tokenization dictionary
sub loadDictionary {
	my $this=shift;
	my $name=shift;
	my $dicsHash=shift;
	my $lang=$this->{language};
	
	$this->printTrace("Loading dictionary $name.$lang.txt\n");

	# Les dictionnaires sont des hachages de hachages enregistrant des regexp. Structure : $dics{nomDico}{lang} -> /regexpr/
	my $dicFilePath=$this->{dicPath}."/$lang/$name.$lang.txt";
	if (open(DICO,"<:encoding(utf8)",$dicFilePath)) {
		my $expr=<DICO>;
		$expr=~s/[\r\n]+$//g;	# chomp
		while (!eof(DICO)) {
			my $line=<DICO>;
			$line=~s/[\r\n]+$//g;
			$expr.="|".quotemeta($line);
		}
		close(DICO);
		$dicsHash->{$name}=qr/^($expr)(.*)/;
		$this->printTrace("dics {$name} -> /$expr/\n");
	} else {
		$this->printTrace("Unable to open dictionary $dicFilePath\n",{warn=>1});
		return 0;
	}
	return 1;
}

# loading abreviations dic

sub loadAbbrevDic {
	my $this=shift;
	my $lang=shift;

	if (exists($this->{abbrevDic}{$lang})) {
		$this->printTrace("abbreviation dic for language $lang already loaded.\n");
		return 1;
	}
	
	$this->printTrace("Loading abbreviation dic for language $lang\n");
	$this->{abbrevDic}{$lang}=[];

	my $dicFilePath=$this->{dicPath}."/$lang/abbrev.$lang.txt";
	
	if (-f $dicFilePath) {
		my @abbrevDic;
		open(abbrev,"<:encoding(utf8)",$dicFilePath) or "die pb with $dicFilePath $.\n";
		while (!eof(ABBREV)) {
			my $line=<ABBREV>;
			$line=~s/[\r\l\n]+$//g;
			push(@abbrevDic,"\\Q".$line."\\E");
		}
		close(ABBREV);
		my $re=join("|",@abbrevDic);
		$this->{abbrevDic}{$lang}=qr/$re/;

	} else {
		$this->printTrace("The abbreviation file $dicFilePath does not exists.\n",{warn=>1});
	}
	return 1;
}


#  loading tokenization grammar
sub loadTokGrammar {
	my $this=shift;
	my $lang=shift;
	

	if (exists($this->{tokenizationGrm}{$lang})) {
		$this->printTrace("Tokenization grammar for language $lang already loaded.\n");
		return 1;
	}
	
	$this->printTrace("Loading tokenization grammar for language $lang\n");
	$this->{tokenizationGrm}{$lang}=[];
	$this->{tokenizationDic}{$lang}={};

	my $grmFilePath=$this->{grmPath}."/$lang/tokenization.rules.$lang.txt";
	
	if (-f $grmFilePath) {
		open(RULES,"<:encoding(utf8)",$grmFilePath) or "die pb with $grmFilePath $.\n";
		while (!eof(RULES)) {
			my $line=<RULES>;
			$line=~s/[\r\l\n]+$//g;
			if ($line=~/<token type="(\w+)">\t([^\t#]+)/) {
				my $type=$1;
				my $expr=$2;
				if ($expr=~/<(\w+)>/) {
					my $dicName=$1;
					if ($this->loadDictionary($dicName,$this->{tokenizationDic}{$lang})) {
						push(@{$this->{tokenizationGrm}{$lang}},{type=>$type,dicName=>$dicName});
						$this->printTrace("Add rule : $lang -> type=$type, dicName=$dicName\n");
					} else {
						$this->printTrace("Warning : dico $dicName unknown for $lang language. The rule '$line' will be ignored\n");
					}
				} else {
					push(@{$this->{tokenizationGrm}{$lang}},{type=>$type,regex=>qr/^($expr)(.*)/});
					$this->printTrace("Add rule : type=$type, regex=$expr\n");
				}
			}
		}
		close(RULES);
		# space character processing
		push(@{$this->{tokenizationGrm}{$lang}},{type=>"spc",regex=>qr/^(\s+)(.*)/});
		# isolated char processing
		push(@{$this->{tokenizationGrm}{$lang}},{type=>"char",regex=>qr/^(.)(.*)/});

	} else {
		$this->printTrace("The grammar file $grmFilePath does not exists. Default rules are used.\n",{warn=>1});
		$this->{tokenizationGrm}{$lang}=$this->{defaultTokRules};
	}
			
	return 1;
}

# private function that loads tagsets translation tabel (between "TT" and "tagset")
# conventionaly, "TT" is the original tagging tagset, and "tagset" is the simplified target tagset
sub loadTagset {
	my $this=shift;
	my $gramPath=$this->{grmPath};
	my $lang=$this->{language};
	my $tagsetName=$this->{tagsetName};
	$this->{tagset2TT}={};
	$this->{TT2tagset}={};
	if (-f $gramPath."/$lang/$tagsetName.$lang.txt") {
		$verbose && print "Loading tagsets from $gramPath/$lang/$tagsetName.$lang.txt\n";
		if (open(TAGSET,"<",$gramPath."/$lang/$tagsetName.$lang.txt")) { 
			while (! eof(TAGSET)) {
				my $line=<TAGSET>;
				$line=~s/\x0D?\x0A?$//; # chomp
				if ($line=~/(.*)\t(.*)/) {
					# tagset2TT
					if (!exists($this->{tagset2TT}{$lang})) {
						$this->{tagset2TT}{$lang}={};
					}
					if (!exists($this->{tagset2TT}{$lang}{$1})) {
						$this->{tagset2TT}{$lang}{$1}=$2;
						#~ $verbose && print "$lang : $1 -> $2\n";
					} else {
						$this->{tagset2TT}{$lang}{$1}.="|".$2;
					}
					# TT2tagset2
					if (!exists($this->{TT2tagset}{$lang})) {
						$this->{TT2tagset}{$lang}={};
					}
					if (!exists($this->{TT2tagset}{$lang}{$2})) {
						$this->{TT2tagset}{$lang}{$2}=$1;
					} else {
						$this->{TT2tagset}{$lang}{$2}.="|".$1;
					}
				}
			}
			close(TAGSET);
		} else {
			$this->printTrace("Unable to open the tagset file $gramPath/$lang/$tagsetName.$lang.txt\n",{warn=>1});
		}
	} else {
		$this->printTrace("File not found : $gramPath/$lang/$tagsetName.$lang.txt\n",{warn=>1});
	}
}

# private function that loads tagsets labels in a specific target language
sub loadTagsetLabels {
	my $this=shift;
	my $gramPath=$this->{grmPath};
	my $lang=$this->{language};
	my $labelLang=$this->{labelLanguage};
	my $tagsetName=$this->{tagsetName};
	$this->{tagsetLabels}{$lang}={};
	if (-f $gramPath."/$lang/$tagsetName.$lang.labels.$labelLang.txt") {
		$verbose && print "Loading tagsets labels from $gramPath/$lang/$tagsetName.$lang.labels.$labelLang.txt\n";
		if (open(TAGSETLABELS,"<:encoding(utf8)",$gramPath."/$lang/$tagsetName.$lang.labels.$labelLang.txt")) { 
			while (! eof(TAGSETLABELS)) {
				my $line=<TAGSETLABELS>;
				$line=~s/\x0D?\x0A?$//; # chomp

				if ($line=~/(.*)\t(.*)/) {
					$this->{tagsetLabels}{$lang}{$1}=$2;
				}
			}
			close(TAGSETLABELS);
		} else {
			$this->printTrace("Unable to open the tagset file $gramPath/$lang/$tagsetName.$lang.txt\n",{warn=>1});
		}
	} else {
		$this->printTrace("File not found : $gramPath//$lang/$tagsetName.$lang.labels.$labelLang.txt\n",{warn=>1});
	}
}

# private function used by search()
# search expression is transformed into regex
sub calcSearchPattern {
	my $this=shift;
	my $searchExpr=shift;
	my $tagset=shift;
	my $resultPat="";
	
	my @toks=split(/ /,$searchExpr);
	foreach my $tok (@toks) {
		my $formPat='[^\t\n]+';
		my $lemmaPat='[^\t]+';
		my $catPat='[^\t]+';
		my $repeat='';
		# the token is express as <w=.*,l=.*,c=.*>
		if ($tok=~/^<(.*)>(.*)/) {
			if ($2) {
				$repeat=$2;
			}
			if ($1) {
				my $content=$1;
				if ($content=~/w=([^,]*)/) {
					$formPat=$1;
				}
				if ($content=~/l=([^,]*)/) {
					$lemmaPat=$1;
				}
				if ($content=~/c=([^,]*)/) {
					$catPat=$1;
				}
			}
		} elsif ($tok=~/^%(.*)/) {
			$lemmaPat=$1;
		} elsif (exists($tagset->{$tok})) {
			$catPat=$tagset->{$tok};
		} elsif ($this->{privateTagset} && exists($this->{privateTagset}->{$tok})) {
			$catPat=$this->{privateTagset}->{$tok};
		} else {
			print "$tok reconnu comme forme\n";
			$formPat=$tok;
		}
		
		$resultPat.='(?:(?<=\n)'.$formPat.'\t'.$catPat.'(?::\w*)?\t'.$lemmaPat.'(?:\n|$)(?:<[^>]+>\s*)*?)'.$repeat;
	}
	return $resultPat;
}

# compute the output string corresponding to a given token, in the desired format
sub outputTokens {
	my $expr=shift;
	my $outputFormat=shift;
	my $tokenSeparator=shift;
	
	my $result="";
	my @toks=split(/\n/,$expr);
	
	
	foreach my $tok (@toks) {
		if ($tok=~/<[^>]+>/) {
			if ($outputFormat eq "xml") {
				$result.=$tok."\n";
			}
		} else {
			my ($form,$cat,$lemma)=split(/\t/,$tok);
			if ($outputFormat=~/xml|tei|ces/) {
				$form=toXml($form);
				$cat=toXml($cat);
				$lemma=toXml($lemma);
			}
			if ($outputFormat eq "xml") {
				$result.="<t orth=\"$form\" base=\"$lemma\" ctag=\"$cat\" />\n";
			} elsif ($outputFormat eq "tei") {
				$result.="<w lemma=\"$lemma\" type=\"$cat\">$form</w>\n";
			} elsif ($outputFormat eq "ces" && ($lemma or $cat) ) { 			# !!!! il faudrait enregistrer la tokenisation comme propriété du fichier
				$result.="<tok base=\"$lemma' ctag=\"$cat\">$form</tok>\n";
			} else {
				$result.=$tokenSeparator.$form;
			}
		}
	}
	return $result;
}

sub toXml {
	my $string=shift;
	
	$string=~s/&/&amp;/g;
	$string=~s/</&lt;/g;
	$string=~s/>/&gt;/g;
	$string=~s/"/&quot;/g;
	return $string;
}

# Converts an given expression in concatenation of forms, categories (POS) or lemmas - if $countBy is query, than only the query number is returned
# This key is used in statistics computation
sub countKey {
	my $expr=shift;
	my $countBy=shift;
	my $queryIndex=shift;
	
	if ($countBy eq "query") {
		return $queryIndex;
	}
	
	my $result="";
	my @toks=split(/\n/,$expr);
	foreach my $tok (@toks) {
		if ($tok!~/<[^>]+>/) {
			my ($form,$cat,$lemma)=split(/\t/,$tok);
			if ($countBy eq "form") {
				$form=~s/^\s+|\s+$//g;
				$result.=" ".$form;
			} elsif ($countBy eq "cat") {
				$result.=" ".$cat;
			} elsif ($countBy eq "lemma") {
				$result.=" ".$lemma;
			}
		}
	}
	$result=~s/^ //;
	return $result;
}
sub toBytes {
	my $string=shift;
	return encode_utf8($string);
}
sub fromBytes {
	my $string=shift;
	return decode_utf8($string);
}

#*************************************************
# simple SAX method for XML parsing. Free callback function are required for  startTag(), pcData() and endTag()
sub parseXMLFile {
	my $file = shift;
	my $encoding = shift;
	my $startTagCallBack=shift;
	my $endTagCallBack=shift;
	my $pcDataCallBack=shift;
	my $refData=shift;
	my $theText="";

		
	my ($tag, $attr, $tagAttr,$avant,$dedans,$notEOF,$notEOF2,$simple);
	my ($IN,$OUT);
	my @listeAttr;
	$/=">";


	open($IN,"<:encoding($encoding)",$file);
	
	# boucle de lecture. A chaque itération, on lit le texte (éventuellement vide) et la prochaine balisse
	while (<$IN>) {

        if (/(.*)<(.*)>$/s) {
			($avant,$dedans)=($1,$2);
			if ($avant) {
				$theText=$avant;
				$pcDataCallBack->(\$theText,$refData);
			}
			# traitement des balises fermantes
			if ($dedans=~/^\/((.|\n)*)/) {	# lecture d'une balise fermante
				$endTagCallBack->($1,\$theText,$refData);
			# traitement des balises ouvrantes
			} else {
				if ($dedans=~/^(\?.*\?)$/s) { #balise <?xml .... ?>
					$tag=$1;
					$attr="";
					$simple="";
				} elsif ($dedans=~/^\s*([^\s]+)\s*(.*?)(\/\s?)$/) { 
					$tag=$1;
					$attr=$2;
					$simple=$3;
				} else {
					$dedans=~/^\s*([^\s]+)\s*(.*?)$/;
					$tag=$1;
					$attr=$2;
					$simple="";
				}
				my %listeAttr;
				# Boucle d'analyse de la liste d'attribut. On se base sur ... ="..."
				while ($attr ne "") {
					if ($attr=~/^([^=\s]+)\s*=\s*(["'])(.*?)\2\s*(.*)/) {
						$listeAttr{$1}=$3;
						$attr=$4;
					} elsif ($attr=~/^([^=\s]+)\s*=\s*([^\s]*)\s*(.*)/) {
						$listeAttr{$1}=$2;
						$attr=$4;
					} else {
						$attr="";
					}
				}
				$startTagCallBack->($tag,$simple,\%listeAttr,\$theText,$refData); 
			}
		} else {
			if (! eof($IN)) {
				print STDERR "Bad XML encoding : $_\n";
				return 0;
			}
		}
	}
	close($IN);
	$/="\n";
	return 1

}

# parsing XML
# lecture sur arg2 car. par car. jusqu'à la lecture du car. passé en arg1
sub lireJusqua {
	my $stopCar=shift;
	my $IN=shift;
	my $refBuffer=shift;
		
	my ($lu,$found);

	$found=0;

	while (1) {
		if ($$refBuffer=~/^(.*?)$stopCar(.*)$/s) {
			$lu=$1;
			$$refBuffer=$2;
			$found=1;
			last;
		}
		if (!eof($IN)) {
			$$refBuffer.=<$IN>;
		} else {
			$lu=$$refBuffer;
			$$refBuffer="";
			last;
		}
	}
	return ($lu,$found);
}

# opening dbm
sub dbmOpen {
	my ($hashRef,$fileName,$mode)=@_;
	my $res;
	if ($useDbFile) {
		print "opening $fileName with mode=$mode\n";
		$res=tie %{$hashRef}, 'DB_File', $fileName or print "Error: $!" ;
	} else {
		$res=dbmopen( %{$hashRef}, $fileName,$mode);
	}
	return $res;
}
# closing dbm
sub dbmClose {
	my $hashRef=shift;
	
	if ($useDbFile) {
		untie %{$hashRef};
	} else {
		dbmclose(%{$hashRef});
	}
}

sub simpleTokenizer {
	my $string=shift;

	my @tokens=split(/(?<=[\W])/,$string);
	my @toks;
	foreach my $tok (@tokens) {
		if ($tok eq " " && $#toks>-1) {
			$toks[$#toks].=" ";
		} else {
			push(@toks,$tok);
		}
	}
	return join("\n",@toks)."\n";
}

sub inArray {
	my $needle=shift;
	foreach my $elt (@_) {
		if ($elt eq $needle) {
			return 1;
		}
	}
	return 0;
}

1;
