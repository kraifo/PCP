package Crawler;

# todo : enregistrer les métadonnées au moment du record, pour les enregistrer également pour les fichiers alignés

# pragma

use strict;
use locale;
use utf8;
#~ use DB_File;
use File::Basename qw(dirname);
use File::Path qw(make_path);
#~ use XML::XPath;
#~ use XML::XPath::XMLParser;

# required : File::Type (type > cpan install File::Type)  

# modules utilisés
use Encode;
use LWP::Simple;
use LWP::UserAgent;
use IO::Handle;
use Try::Tiny;

#~ use File::Type;
STDOUT->autoflush(1);
binmode(STDOUT, ":utf8");

#------------------------------------------------------------------------------------------------
# 
use Exporter;


our @ISA = qw(Exporter);
our @EXPORT = qw( &new &runCrawler &addSource );
our @EXPORT_OK = qw( );	
our $VERSION	= '2.0';

BEGIN {
}

#------------------------------------------------------------------------------------------------
# global parameters


my $defaultParam= {
	verbose=>1,													# if 1, display execution trace on STDOUT 
	printLog=>1,												# if 1, print execution trace in a log file 
	overwriteLog=>1,											# if 1, the log file is named crawler.pl.log - if 0 it is named with date and time crawler.pl.yyyy-mm-dd.hh-mm-ss.log
	outputDir=>'./data/crawler',
	metadataFilePattern=>[qr/(.*)/,'$1.meta'],						# if not empty, defines the name of the corresponding metadata file
};

# Warning : all parameters must be defined in the default values
my $defaultSource={
	# crawling rules
	url=>'',
	urlPattern=>'',
	otherLinkPattern=>'',
	indexDepth=>3,
	indexPagePattern=>'',
	paginationUrlPattern=>'',
	sourceLanguage=>'',
	limitDepth=>100,
	latency=>0.1,
	noFormData=>0,
	blackListUrlPattern=>'',
	postData=>[],
	resetCrawling=>0,					# if 1, delete hash %visited
	# content rules
	nameBase=>'url',					# ('url'|'content'|'id')
	namePattern=>[qr/[\\\/?&:*]/,'_'],	# [/pattern/,replace]
	metadataPatterns=>[
		{
			label=>'title',	
			base=>'url',
			search=>qr/(.*)/,
			replace=>'$1'
		}
	],
	saveFullHtml=>0,
	url2download=>'',
	contentXpath=>'',
	contentPattern=>'',
	inputEncoding=>'cp-1252',
	outputEncoding=>'cp-1252',
	guessFileType=>0,
	maxRecordedPages=>10,
	# **************************** aligned url rules
	sourceLanguage=>'fr',
	downloadIfAligned=>0,
	alignedUrlPatterns=>{},				# Method 1.a: definition of the pattern of aligned url
	alignedLinkPatterns=>{}, 			# Method 1.b: definition of the pattern of the aligned link
	alignedUrlWithContextPatterns=>{},	# Method 1.c: used when looking for an aligned url in the page
	alignedUrlTransformationScheme=>{}, # Method 2 : used to transform the current url in an aligned url
	correspondingUrlPattern=>{} 		# Method 3 : used to analyze an index page with pairs of corresponding url
};

# global data structure

my  %visited;		# DBM : storing already visited pages
					# key : url 
					# value : page id
				
my  %currentVisited;# records the pages that are visited during current session
					# key : url 
					# value : page id
my %correspondingUrl; # records the aligned url when found by the correspondingUrlPattern
my $globalCount=0;# the global number of visited pages in order to limit the crawling during the current session

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst); # recording the time of object creation

#------------------------------------------------------------------------------------------------

# public methods


# constructor of the main object : the pipeline for which all the processes will be done
sub new {
	my $class=shift;
	my $param=shift;
	my $this={};
	bless ($this,$class);
	$this->setParam($defaultParam);
	$this->setParam($param);
	
	my $dirname=$this->{outputDir};
	
	# creating file directory
	if (-f $dirname) {
		$this->printTrace("$dirname already exists as a file and cannot be used as a directory.\n",{warn=>1});
		return 0;
	}
	if (! -e $dirname) {
		$this->printTrace("Creating directory $dirname\n");
		my $res=make_path($dirname);
		if (! $res) {
			$this->printTrace("A problem occurs while creating direrctory $dirname\n",{warn=>1});
			return 0;
		}
	}

	
	# open the log file if necessary
	if ($this->{printLog}) {
		my $logFile=$this->{outputDir}."/crawler.pl.log";
		if ($this->{overwriteLog}==0) {
			$logFile=$this->{outputDir}."crawler.pl.$year-$mon-$mday.$hour-$min-$sec.log";
		}
		open (LOG,">",$logFile);
	}
	
	# updating value for global var with localtime
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$year+=1900;
	
	return $this;
}

#*************************************************************************** setParam($param,$options)

# set param values according to the key->value pairs of the hash
# if $options->{noOverwrite} is set to 1, new param will not overwrite olders
sub setParam {
	my $this=shift;
	my $hash=shift;
	my $options={noverwrite=>0};
	if (@_) {
		$options=shift;
	}
	
	foreach my $key (keys %{$hash}) {
		if (! exists($this->{$key}) || ! $options->{noOverwrite}) {
			$this->{$key}=$hash->{$key};
		}
	}
}

#*************************************************************************** addSource($source)
# adding a new source to obj->sources list

sub addSource {
	my $this=shift;
	my $sourceParam=shift;
	
	my $newSource={};
	# copying default values
	foreach my $key (keys %{$defaultSource}) {
		if (! defined($sourceParam) or ! exists($sourceParam->{$key})) {
			if (exists($this->{$key})) {
			# copying from the pipeline object
				$newSource->{$key}=$this->{$key};
			} else {
			# copying from the default
				$newSource->{$key}=$defaultSource->{$key};
			
			}
		} else {
			$newSource->{$key}=$sourceParam->{$key};
		}
	}
	# if id is not defined, using numbers
	if (!exists($this->{sourceId})) {
		$newSource->{id}=@{$this->{sources}}+1;
	} else {
		$newSource->{id}=$this->{sourceId};
	}
	
	# by default target directory is outputDir/id
	if (! exists($this->{targetDir})) {
		$newSource->{targetDir}=$this->{outputDir}."/".$newSource->{id};
	} else {
		$newSource->{targetDir}=$this->{targetDir};
	}
	
	my $dirname=$newSource->{targetDir};
	
	# creating target directory for current source
	if (-f $dirname) {
		$this->printTrace("$dirname already exists as a file and cannot be used as a directory.\n",{warn=>1});
		return 0;
	}
	if (! -e $dirname) {
		$this->printTrace("Creating directory $dirname\n");
		my $res=make_path($dirname);
		if (! $res) {
			$this->printTrace("A problem occurs while creating direrctory $dirname\n",{warn=>1});
			return 0;
		}
	}

	
	push (@{$this->{sources}},$newSource);
}

#*************************************************************************** runCrawler()

# Run crawling for each source
# Input :
# arg1 : the crawl object

sub runCrawler {
	my $this=shift;

	my $sources=$this->{sources};
	
	# updating value for global var with localtime
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$year+=1900;

	$globalCount=0;
	
	# main loop : crawling is done for each $source
	foreach my $source (@{$sources}) {
		$this->printTrace( "Processing of source : $source->{id}\n" );
		if (! -e $source->{targetDir}) {
			my $res=make_path($source->{targetDir});
			if (! $res) {
				$this->printTrace("Unable to create $source->{targetDir}\n",{warn=>1});
				return 0;
			}
		}
		
		%visited=();
		%currentVisited=();
		dbmopen (%visited, $source->{targetDir}.'/visited', 0640) or die $!;
		if ($source->{resetCrawling}) {
			%visited=();
		}
		open(METADATA,">>",$source->{targetDir}.'/metadata');
		print METADATA "\nCrawling date\turl\tfilename\ttitle\tid\n\n";
		$this->Crawler::crawl($source,$source->{url},"",0);
		close(METADATA);
		dbmclose(%visited);
	}
}

# recursive crawling of $source, and saving pages in $targetDir
sub crawl {
	my $this=shift;
	my $source=shift;
	my $url=shift;
	my $linkText=shift;
	my $depth=shift;

	# NOTE : all the source parameter MUST be initialized in the default values
	my $id=$source->{id};
	my $targetDir=$source->{targetDir};
	my $urlPattern=$source->{urlPattern};
	my $contentPattern=$source->{contentPattern};
	my $contentXpath=$source->{contentXpath};
	my $saveFullHtml=$source->{saveFullHtml};
	my $blackListUrlPattern=$source->{blackListUrlPattern};
	my $url2download=$source->{url2download};
	my $nameBase=$source->{nameBase};
	my $namePattern=$source->{namePattern};
	my $postData= $source->{postData};
	my $limitDepth= $source->{limitDepth};
	my $inputEncoding=$source->{inputEncoding};
	my $outputEncoding=$source->{outputEncoding};
	my $indexDepth=$source->{indexDepth};
	my $indexPagePattern=$source->{indexPagePattern};
	my $guessFileType=$source->{guessFileType};
	my $noFormData=$source->{noFormData};
	my $maxRecordedPages=$source->{maxRecordedPages};
	my $paginationUrlPattern=$source->{paginationUrlPattern};
	my $latency=$source->{latency};


	# Processing a list of starting urls
	# if $url is a reference to a callback function, the callback is called to compute a list of url and crawl is recursively called on each url
	if (ref $url eq "CODE") {
		foreach my $u ($url->()) {
			$this->crawl($source,$u,$linkText,$depth);
		}
	# if  $url is a reference to a list
	} elsif (ref $url eq "ARRAY") {
		foreach my $u (@{$url}) {
			$this->crawl($source,$u,$linkText,$depth);
		}
	}
	
	# adding url2download to urlPattern
	if ($url2download) {
		$urlPattern=qr/$urlPattern|$url2download/;
	}
	
	# end of recursion
	if ($depth >= $limitDepth) {
 		$this->printTrace( "Max depth is reached\n");
		return ;
	}
	if ($depth>0 && $urlPattern && $url!~$urlPattern )  {
		$this->printTrace( "$url does not match to /$urlPattern/\n");
		return;
	}
	if ($blackListUrlPattern && $url=~/$blackListUrlPattern/)  {
		$this->printTrace("$url is blacklisted (blacklist=$blackListUrlPattern)\n");
		return;
	}

	# if the page has been visited during the current session, skip
	if (exists($currentVisited{$url})) {
		return;
	}	
	
	# if the page has been visited in a previous session, skip (but for indexPage or paginationUrl)
	if (	defined($visited{$url}) && 
		! ($url eq $this->{url}) &&
		! ( $indexPagePattern ne '' && $url=~/$indexPagePattern/ ) &&
		! ( $paginationUrlPattern ne '' && $url=~/$paginationUrlPattern/ )
	) {
		$this->printTrace("$url has already been visited in a previous session\n");
		return ;
	}


	 
	$currentVisited{$url}=1;
	
	select(undef, undef, undef, $latency); #  waiting 0.1 sec. to avoid blacklisting
 
	# processing page
	$this->printTrace("\n\n###################### Processing $url\n");
	my ($page,$contentType,$location)=$this->Crawler::getContent($url,$postData,$source->{inputEncoding});

	if (! $page)  {
		# using simple get() method
		$page=get($url);
		if (! $page) {
			# if invalid url, give up
			$this->printTrace("Page $url cannot be downloaded",{warn=>1});
			return;
		}
	}

	# link extraction
	my ($crawlingLinks,$alignedLinks)=$this->Crawler::extractUrl($page,$url,$urlPattern,$noFormData);
	my %links=%{$crawlingLinks};
	
	# looking for aligned links !!!!
	# Method 1a / 1b : the url has been found according to alignedLinkPatterns or alignedUrlPatterns
	my %alignedLinks=%{$alignedLinks};
	my $aligned=0;
	if (keys %alignedLinks) {
		$aligned=1;
	} 
	# Method 1.c : look for an aligned url in the page, relying on context
	elsif ($this->{alignedUrlWithContextPatterns}) {
		foreach my $language (keys %{$this->{alignedUrlWithContextPatterns}}) {
			if ($page=~/$this->{alignedUrlWithContextPatterns}{$language}/) {
				my $href=$1;
				my ($domain,$path)=Crawler::calcDomainPath($page,$url);
				my $alignedUrl=Crawler::calcUrl($domain,$path,$href);
				
				my $ua= LWP::UserAgent->new(  agent => "Mozilla/5.0 (X11; Ubuntu; Linux i686; rv:28.0) Gecko/20100101 Firefox/28.0");
				my $response=$ua->head($alignedUrl);
				if ($response->is_success && not $response->{_previous}) {
					$alignedLinks{$language}=$alignedUrl;
					$this->printTrace("A translated link has been found on the page, for the language $language:\n-->$alignedUrl\n");
					$aligned=1;
				}
			} 
		}
	}
	# Method 2 : if a transformation scheme exists, and no aligned link has been foundn apply the transformation scheme to find all aligned pages
	elsif ($this->{alignedUrlTransformationScheme}) {
		foreach my $language (keys %{$this->{alignedUrlTransformationScheme}}) {
			my $pattern=$this->{alignedUrlTransformationScheme}{$language}[0];
			my $replace=$this->{alignedUrlTransformationScheme}{$language}[1];
			my $alignedUrl=$url;
			$alignedUrl=~s/$pattern/'"'.$replace.'"'/ee;
			if ($alignedUrl ne $url) {
				my $ua= LWP::UserAgent->new(  agent => "Mozilla/5.0 (X11; Ubuntu; Linux i686; rv:28.0) Gecko/20100101 Firefox/28.0");
				my $response=$ua->head($alignedUrl);
				if ($response->is_success && not $response->{_previous}) {
					$alignedLinks{$language}=$alignedUrl;
					$this->printTrace("A translated link has been found on the page, for the language $language:\n-->$alignedUrl\n");
					$aligned=1;
				}
			} 
		}
	} 

	# Method 3 : if a pattern allows to find the aligned url pairs in the current page, we can feed the hash %correspondingUrl,
	# which will be used later
	if ($this->{correspondingUrlPattern}) {
		foreach my $language (keys %{$this->{correspondingUrlPattern}}) {
			while ($page=~/$this->{correspondingUrlPattern}{$language}/) {
				my $url1=$+{'href1'};
				my $url2=$+{'href2'};
				my ($domain,$path)=Crawler::calcDomainPath($page,$url);
				$url1=calcUrl($domain,$path,$url1);
				$url2=calcUrl($domain,$path,$url2);
				$correspondingUrl{$url1}{$language}=$url2;
				$this->printTrace("Corresponding urls have been found : $url1 => $url2.\n");
			}
		}
	}
	
	$this->printTrace((keys %links)." links has been found on the page.\n");
	if ($aligned) {
		$this->printTrace((keys %alignedLinks)." aligned links has been found on the page.\n");
	}

	# if current page has not been recorded yet, or is not an index page
	if (!  defined($visited{$url}) or ($indexPagePattern ne '' && $url=~/$indexPagePattern/) or ($depth <= $indexDepth)) {
		
		$this->printTrace("Now looking for content in the page\n");
		if (!defined($visited{$url})) {
			if (!defined($visited{"last"})) {
				$visited{"last"}=0;
			}
			$visited{"last"}++;
			$visited{$url}=$visited{"last"};		   # updating the hash of visited pages
		}
		my $id=$visited{$url};


		
		# computing file name
		my $languageSuff;
		if ($source->{sourceLanguage}) {
			$languageSuff=".".$source->{sourceLanguage};
		}
		my $downloadedFileName;
		
		# download of the content if any
		if (!$this->{downloadIfAligned} or %alignedLinks) {
			$downloadedFileName=$this->Crawler::recordContent($source,$url,$linkText,$page,$id,$languageSuff,"");
			
			# looking for alignedUrl in the extracted links, if some content has been saved
			if (%alignedLinks && $downloadedFileName) {
				LINKEDURL:while (my ($lang,$linkedUrl)=each %alignedLinks) {
					$this->printTrace("----> Found an aligned URL for language $lang\n");
					my ($alignedPage,$contentType,$location)=$this->Crawler::getContent($linkedUrl,[],$source->{inputEncoding});
					if (! $alignedPage)  {
						# using simple get() method
						$alignedPage=get($linkedUrl);
						if (! $alignedPage) {
							# if invalid url, give up
							$this->printTrace("Aligned page $linkedUrl cannot be downloaded",{warn=>1});
							next LINKEDURL;
						}
					}
					my $alignedFileName=$downloadedFileName;
					# replacing the suffix
					$alignedFileName=~s/[.]?$languageSuff[.](\w+)$/.$lang.$1/;
					$this->printTrace("----> downloading the aligned page to file $alignedFileName\n");
					# the aligned filename is given as an argument (and should not be computed)
					$this->Crawler::recordContent($source,$linkedUrl,$linkText,$alignedPage,$id,"",$alignedFileName);
				}
			}
		}

		# If the file has been donwloaded
		if ($downloadedFileName) {
			$globalCount++;
		} else {
			if ($this->{downloadIfAligned} && ! %alignedLinks) {
				$this->printTrace("Content has been found but no page is aligned with $url\n");
			} else {
				$this->printTrace("No content found in $url\n");
			}
		}
	}
	 
	if ($location) {
		$this->printTrace("Redirection to $location\n");
		$url=$location;
	}
	
	# recursion 
	while (my ($link,$linkText)= each %links) {
		if ($maxRecordedPages && $globalCount <$maxRecordedPages) {	# global limit for testing
			my $nextDepth=$depth;
			# incrémentation de la profondeur, sauf pour les url de pagination
			if ($url!~/$paginationUrlPattern/) {
				$nextDepth++;
			}
			$this->Crawler::crawl($source,$link,$linkText,$nextDepth);
		} else {
			$this->printTrace("Limit of $maxRecordedPages pages has been reached for this session\n");
			return;
		}
	}
}

# Function that records either the full page either a selected pattern, according to url2download or contentPattern parameters
# If a file is recorded, metadata are recorded as well
sub recordContent {
	my $this=shift;
	my $source=shift;
	my $url=shift;
	my $linkText=shift;
	my $page=shift;
	my $id=shift;
	my $language=shift;
	# if $downloadedFileName is originally empty, it will be computed and returned as a result
	my $downloadedFileName=shift;
		
	# CASE 1 : the url matches : downloading the complete document
	if($source->{url2download} && $url=~/$source->{url2download}/) {
		my $name=$this->Crawler::calcTargetFileName($source,$url,$page,$id);
		#~ print "################### $url\n";

		my $type="";
		if ($source->{guessFileType}) {
			if ($source->{contentType}=~/\w+\/(\w+)/) {
				$type=".".$1;
			}
			#~ my $ft = File::Type->new();
			#~ $type= $ft->mime_type($page);
			#~ $type=~s/.*\///;
			#~ $type=".".$type;
		}
		if (! $downloadedFileName) {
			$downloadedFileName=$name.$language.$type;
		}
		$this->printTrace("###### Recording page $url with name $downloadedFileName\n");
		if ($source->{outputEncoding} ne "bin") {
			open(OUT,">:encoding(".$source->{outputEncoding}.")",$downloadedFileName);			# copie de la page
		} else {
			open(OUT,">:raw",$downloadedFileName);			# copie de la page
		}
		print OUT $page;
		close OUT;
		
	# CASE 2 : the content is filtered and only the matching part is saved
	} elsif ($source->{contentPattern}) {
		if (ref $source->{contentPattern} eq "HASH") {
			my $search=1;
			if ($this->{findAllContentPattern}) {
				IDCONTENT:foreach my $idContent (keys %{$source->{contentPattern}}) {
					if ($page!~/$source->{contentPattern}{$idContent}/is) {
						$search=0;
						last IDCONTENT;
					}
				}
			}
			if ($search) {
				foreach my $idContent (keys %{$source->{contentPattern}}) {
					if ($page=~/$source->{contentPattern}{$idContent}/is) {
						my $name=$this->Crawler::calcTargetFileName($source,$url,$page,$id);
						my $content=$1;
						# if the capturing group is named 'content'
						if (exists($+{'content'})) {
							$content=$+{'content'};
						}

						if (!defined($content)) {
							$this->printTrace("Pattern /$source->{contentPattern}{$idContent}/ has been found but content is empty \n\n",{warn=>1});
						} else {
							if (! $downloadedFileName) {
								$downloadedFileName=$name.".$idContent$language.html";
							}
							$this->printTrace("Recording in $downloadedFileName the string matching with \$1 in pattern: \n/$source->{contentPattern}/\n\n");
							if ($source->{outputEncoding} ne "bin") {
								open(OUT,">:encoding(".$source->{outputEncoding}.")",$downloadedFileName);
							} else {
								open(OUT,">:raw",$downloadedFileName);
							}
							print OUT $content;
							close OUT;
						}
					}
				}
			}
		} elsif ($page=~/$source->{contentPattern}/is) {
			my $name=$this->Crawler::calcTargetFileName($source,$url,$page,$id);
			my $content=$1;
			# if the capturing group is named 'content'
			if (exists($+{'content'})) {
				$content=$+{'content'};
			}
			if ($this->{multipleContent}) {
				$content="";
				while ($page=~/$source->{contentPattern}/gis) {
					$content.=$1;
				}
			}
			
			if ( $source->{saveFullHtml}) {
				if (! $downloadedFileName) {
					$downloadedFileName=$name.$language.".html";
				}
				$this->printTrace("Recording page $url in $downloadedFileName\n");
				if ($source->{outputEncoding} && $source->{outputEncoding} ne "bin") {
					open(OUT,">:encoding(".$source->{outputEncoding}.")",$downloadedFileName);
				} else {
					open(OUT,">:raw",$downloadedFileName);
				}
				print OUT $page;
				close OUT;
			} else {
				# only mathing $content 
				if (!defined($content)) {
					$this->printTrace("Pattern /$source->{contentPattern}/ has been found but content is empty \n\n",{warn=>1});
				} else {
					if (! $downloadedFileName) {
						$downloadedFileName=$name.".extract$language.html";
					}
					$this->printTrace("Recording in $downloadedFileName the string matching with \$1 in pattern: \n/$source->{contentPattern}/\n\n");
					if ($source->{outputEncoding} ne "bin") {
						open(OUT,">:encoding(".$source->{outputEncoding}.")",$downloadedFileName);
					} else {
						open(OUT,">:raw",$downloadedFileName);
					}
					print OUT $content;
					close OUT;
				}
			}
		}
	} elsif ($source->{contentXpath}) {
		# removing comments
		#~ print $page;
		$page=~s/<!--\/\*.*?\*\/-->|<!--[^>]*-->|<!\[CDATA\[.*?\]\]>|<!--\[if .*?\]>|<!\[endif\]-->//gs;

		my $content="";
		try {
			#~ my $xp = XML::XPath->new(xml => $page);
			#~ $this->printTrace("Searching for xpath=$contentXpath\n");

			#~ my $nodeset = $xp->find($contentXpath); # find all content element
			
			#~ print $nodeset->get_nodelist." noeuds trouvés\n";
			#~ foreach my $node ($nodeset->get_nodelist) {
				#~ $content.=XML::XPath::XMLParser::as_string($node);
			#~ }
		} catch {
			warn "Page $url cannot be parsed as XML. Error : $_\n";
		};
		
		# only mathing $content 
		if (! $content) {
			$this->printTrace("Xpath nodes ($source->{contentXpath}) have not been found on the page\n");
		} else {
			my $name=$this->Crawler::calcTargetFileName($source,$url,$page,$id);
			if (!$downloadedFileName) {
				$downloadedFileName=$name.".extract$language.html";
			}
			$this->printTrace("Recording (in $name.extract$language.html) the nodes that match with xPath=$source->{contentXpath}\n\n");
			if ($source->{outputEncoding} ne "bin") {
				open(OUT,">:encoding(".$source->{outputEncoding}.")",$downloadedFileName);
			} else {
				open(OUT,">:raw",$downloadedFileName);
			}
			print OUT $content;
			close OUT;
		}
	} else {
		if (! $source->{url2download} && ! $source->{contentPattern} && ! $source->{contentXpath}) {
			print "No parameter to extract content (cf. url2downolod, or contentPattern, or contentXpath)\n";
		}
	}

	#*************************************************
	# handling metadata if the file has been recorded
	if ($downloadedFileName) {
		my %metadata;
		foreach my $metaPattern (@{$source->{metadataPatterns}}) {
			my $base;
			if ($metaPattern->{base} eq 'content') {
				$base=$page;
			} elsif ($metaPattern->{base} eq 'url') {
				$base=$url;
			} elsif ($metaPattern->{base} eq 'id') {
				$base=$source->{id}."_".$id;
			} elsif ($metaPattern->{base} eq 'linkText') {
				$base=$linkText;
			}
			#~ print "Looking for ".$metaPattern->{search}." in ".$base.'\n';
			if ($base=~ $metaPattern->{search} ) {
				my $string=$1;
				if (exists($metaPattern->{replace})) {
					$base=~ s/$metaPattern->{search}/'"'.$metaPattern->{replace}.'"'/ee;
					$metadata{$metaPattern->{label}}=supprTag($base);
				} else {
					$metadata{$metaPattern->{label}}=supprTag($string);
					#~ print "$metaPattern->{label}=>$1\n";
				}
			} else {
				#~ print "Metadata Not Found for label=$metaPattern->{label}\n";
			}
		}
		
		print METADATA "$year/$mon/$mday\t".$url."\t".$downloadedFileName."\t".$id."\n";
		# printing metadata !!!
		if ($this->{metadataFilePattern}) {
			my $newFileName=$downloadedFileName;
			my $replace = '"'.$this->{metadataFilePattern}->[1].'"';
			$newFileName=~s/$this->{metadataFilePattern}->[0]/$replace/ee; # the trick is to evaluate potential $1, $2, etc.
			if (open(METADATAFILE,">:utf8",$newFileName)) {
				print METADATAFILE "id\t$id\n";
				print METADATAFILE "downloadDate\t$year/$mon/$mday\n";
				print METADATAFILE "url\t$url\n";
				print METADATAFILE "linkText\t$linkText\n";
				while (my ($label,$value) = each %metadata) {
					print METADATAFILE "$label\t$value\n";
				}
				close(METADATAFILE);
			} else {
				$this->printTrace("Unable to write $newFileName\n");
			}
		}

	}

	return $downloadedFileName;
}

# compute the name of the recorded target file
sub calcTargetFileName {
	my $this=shift;
	my $source=shift;
	my $url=shift;
	my $page=shift;
	my $id=shift;
		
	my $nameBase="";
	my $name="";
	if (@{$source->{namePattern}}) {
		if ($source->{nameBase} eq 'content' && $page=~/$source->{namePattern}[0]/) {
			$nameBase=$page;
		}
		if ($source->{nameBase} eq 'url' && $url=~/$source->{namePattern}[0]/) {
			$nameBase=$url;
		}
		if ($source->{nameBase} eq 'id') {
			$nameBase=$source->{id}."_".$id;
		}

		if ($source->{namePattern}[1]) {
			$nameBase=~/$source->{namePattern}[0]/;
			$name=eval('"'.$source->{namePattern}[1].'"');
		} else {
			if ($nameBase=~/$source->{namePattern}[0]/) {
				$name=$1;
			} else {
				$this->printTrace("$source->{namePattern}[0] not found in nameBase. Using number instead\n");
				$name=$source->{id}."_".$id;
			}
		}
	}
	# removing special chars
	$name=~s/[\/:?*]/_/g;
	# char normalisation
	$name=~tr/ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿĀāĂăĄąĆćĈĉĊċČčĎďĐđĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĦħĨĩĪīĬĭĮįİıĲĳĴĵĶķĸĹĺĻļĽľĿŀŁłŃńŅņŇňŉŊŋŌōŎŏŐőŒœŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŦŧŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽžſƀƁƂƃƄƅƆƇƈƉƊƋƌƍƎƏƐƑƒƓƔƕƖƗƘƙƚƛƜƝƞƟƠơƢƣƤƥƦƧƨƩƪƫƬƭƮƯưƱƲƳƴƵƶƷƸƹƺƻƼƽƾƿǀǁǂǃǄǅǆǇǈǉǊǋǌǍǎǏǐǑǒǓǔǕǖǗǘǙǚǛǜǝǞǟǠǡǢǣǤǥǦǧǨǩǪǫǬǭǮǯǰǱǲǳǴǵǶǷǸǹǺǻǼǽǾǿȀȁȂȃȄȅȆȇȈȉȊȋȌȍȎȏȐȑȒȓȔȕȖȗȘșȚțȜȝȞȟȠȡȢȣȤȥȦȧȨȩȪȫȬȭȮȯȰȱȲȳȴȵȶȷȸȹȺȻȼȽȾȿɀɁɂɃɄɅɆɇɈɉɊɋɌɍɎɏɐɑɒɓɔɕɖɗɘəɚɛɜɝɞɟɠɡɢɣɤɥɦɧɨɩɪɫɬɭɮɯɰɱɲɳɴɵɶɷɸɹɺɻɼɽɾɿʀʁʂʃʄʅʆʇʈʉʊʋʌʍʎʏʐʑʒʓʔʕʖʗʘʙʚʛʜʝʞʟʠʡʢʣʤʥʦʧʨʩʪʫʬʭʮʯ/aaaaaaaceeeeiiiidnoooooouuuuytsaaaaaaaceeeeiiiidnoooooouuuuytyaaaaaaccccccccddddeeeeeeeeeegggggggghhhhiiiiiiiiiijjjjkkkllllllllllnnnnnnnnnoooooooorrrrrrssssssssttttttuuuuuuuuuuuuwwyyyzzzzzzqbbbbbboccdddddeeeffgghiikkllmnnoooooppyssssttttuuuvyyzzzzzzzzzkkkkkkzdzlllnnnaaiioouuuuuuuuuueaaaaaaggggkkoooozzjzdzgghwnnaaaaooaaaaeeeeiiiioooorrrruuuussttyyhhnduuzzaaeeooooooooyylntjdqaccltszkkbuveejjqqrryyaaabocddeeeeeeejgggghhhhiiillllmmmnnnooofrrrrrrrrrssjssttuuvvwyyzzzzkrkkpbeghjklqkkzzztttfllpphh/;
	$name=$source->{targetDir}."/".$name;
	
	return $name;
}


#***************************************************************************  PRIVATE METHODS

# Private method that handle the printing of execution trace on STDOUT and in the log file (and warnings on STDERR)
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
	if ($this->{warn}) {
		warn $msg;
	}
}

# But : extraction des hyperliens qui satisfont URL pattern d'une page
# appelée par crawl()
# Entrées :
# arg1 : string -> le contenu d'une page web
# arg2 : string -> l'url de la page (utile pour renvoyer les url en absolu)
# arg3 : string -> pattern du domaine à retenir
# arg4 : string -> url du domaine, pour concaténation
# Sortie : hash -> liste des urls extraites d'hyperliens en absolu (clés -> les valeurs sont les liens)
sub extractUrl {
	my $this=shift @_;
	my $page=shift @_;
	my $currentUrl= shift @_;
	my $urlPattern= shift @_;
	my $noFormData= shift @_;

	my %crawlingLinks;
	
	my ($domain,$path)=Crawler::calcDomainPath($page,$currentUrl);
	
	if (! defined ($domain)) {
		$this->printTrace("invalid URL: $currentUrl -> domain name cannot be read\n ");
		return;
	}

	my %alignedLinks;
			
	while ($page =~/<a[^>]*?href\s*=\s*(["'])([^#][^>]+?)\1[^>]*>(.*?)<\/a>/sig ) {
		#~ print "$2\n";
		my $url=$2;
		my $href=$url;
		my $linkText=$3;
		$linkText=~s/[\n\r]+//g;
		
		# remplacement d'éventuelles entités &amp;
		$url=Crawler::calcUrl($domain,$path,$href);
		
		# suppression éventuelle des données get dans l'url résultat
		if ($noFormData) {
			$url=~s/[?].*//;
		}
		# on n'enregistre que les url normales
		if ($href !~/^#|mailto:|javascript:|feed:http$/ ) {
			$crawlingLinks{$url}=$linkText;
			# if some corresponding url has been found before
			if (exists($correspondingUrl{$url})) {
				foreach my $lang (keys %{$correspondingUrl{$url}}) {
					$alignedLinks{$lang}=$correspondingUrl{$url}{$lang};
				}
			}
		}
	}

	if ($this->{otherLinkPattern}) {
		while ($page =~ /$this->{otherLinkPattern}/g ) {
			my $url=$1;
			my $href=$url;
			
			# remplacement d'éventuelles entités &amp;
			$url=Crawler::calcUrl($domain,$path,$href);
			
			# suppression éventuelle des données get dans l'url résultat
			if ($noFormData) {
				$url=~s/[?].*//;
			}
			$crawlingLinks{$url}="other";
			# if some corresponding url has been found before
			if (exists($correspondingUrl{$url})) {
				foreach my $lang (keys %{$correspondingUrl{$url}}) {
					$alignedLinks{$lang}=$correspondingUrl{$url}{$lang};
				}
			}

		}
	}
	
	# looking for aligned page

	if ($this->{alignedUrlPatterns}||$this->{alignedLinkPatterns}) {
		LINKEDURL:foreach my $linkedUrl (keys %crawlingLinks) {
			my $patterns;
			# the pattern may be searched either in the url or in the link text
			my $string2test=$linkedUrl;
			if ($this->{alignedUrlPatterns}) {
				$patterns=$this->{alignedUrlPatterns};
			} else {
				$patterns=$this->{alignedLinkPatterns};
				$string2test=$crawlingLinks{$linkedUrl};
			}
			while (my ($lang,$pattern)=each %{$patterns}) {
				if ($string2test=~$pattern) {
					$alignedLinks{$lang}=$linkedUrl;
				}
			}
		}
	}

	
	# deleting non matching url for crawling
	foreach my $k (keys %crawlingLinks) {
		if ($k !~ /$urlPattern/) {
			delete $crawlingLinks{$k};
		}
	}
	return (\%crawlingLinks,\%alignedLinks);
}

# computing the domain and path for the current url
sub calcDomainPath {
	my $page=shift;
	my $currentUrl=shift;
	my ($domain,$path);
	
	# cas où l'entête contient à paramètre base pour la construction des urls relatives
	if ($page=~/<base [^>]*href=(["'])(.*?)\1/) {
		$currentUrl=$2;
	}
	
	# calcul du domaine et du chemin
	if ($currentUrl=~/(https?:\/\/[^\/]+)(.*)/) {
		$domain=$1;
		$path=$2;
	} else {
		return;
	}

	
	# suppression d'éventuelles données get ( url?var=value ou url\?var=value)
	$path=~s/[?].*$//;
	
	# si l'url courante se termine par un nom de fichier, il faut le tronquer
	$path=~s/[^\/]*$//;
	
	return ($domain,$path);
}

# computing the absolute url for a href found in <a>
sub calcUrl {
	my $domain=shift;
	my $path=shift;
	my $href=shift;
	
	my $url=$href;
	$url=~s/&amp;/&/g;
	
	# traitement des chemins relatifs : si l'url commence par un point ou une lettre (mais pas http://
	if ($url=~/^[\.\-\w]/ && $url!~/^http/) {
		my $slash="/";
		if ($path=~/\/$/) {
				$slash="";
		}
		
		$url=$domain.$path.$slash.$url;
	} elsif ($url=~/^\/.+/) {				 	# chemins commençant par "/" : il faut leur concaténéer l'url du domaine, quelle que soit l'url de la page courante  ;
												#  ex : '/voyage/video/2011/11/30/un-voyage-en-porte-conteneurs-1-2_1611334_3546.html'
												# la page courante peut elle-même être un article ; or il faut simplemet concaténer 'http://lemonde.fr' au début de l'url du lien
		$url=$domain.$url;
	}
	# remplacement éventuel de /rep1/../rep2 par rep2
	do {} while ($url=~s/	[^\/]+		# rep1
									\/				# slash
									\.\.			# ..
									\/				# slash
									([^\/]+)		# rep2
									/$1/x);  
	$url=~s/#[^\/]*$//;
	$url=~s/\/[.]\//\//g; # simplification : /./ -> /


	return $url;
}

	
# requête HTTP pour obtenir le contenu de la page. Les données POST sont dans le tableau %postDATA
sub getContent {
	my $this=shift;
	my $url=shift;
	my $postData=shift;
	my $inputEncoding=shift;
#~ Host: www.persee.fr
#~ User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux i686; rv:28.0) Gecko/20100101 Firefox/28.0
#~ Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
#~ Accept-Language: fr,fr-fr;q=0.8,en-us;q=0.5,en;q=0.3
#~ Accept-Encoding: gzip, deflate
#~ DNT: 1
#~ Cookie: slidefirst=true; GUEST_LANGUAGE_ID=fr_FR; COOKIE_SUPPORT=true; __utma=155063993.723518338.1385411618.1397232104.1397237151.11; __utmz=155063993.1396337233.7.5.utmcsr=cairn.info|utmccn=(referral)|utmcmd=referral|utmcct=/revue-langages.htm; AWSUSER_ID=awsuser_id1385411617650r2820; JSESSIONID=B90CFEA795973EF0942DA7179CA7245B.portail3; __utmc=155063993; __utmb=155063993.2.10.1397237151; AWSSESSION_ID=awssession_id1397237150761r1236
#~ Connection: keep-alive
#~ Cache-Control: max-age=0
	my $ua= LWP::UserAgent->new(  agent => "Mozilla/5.0 (X11; Ubuntu; Linux i686; rv:28.0) Gecko/20100101 Firefox/28.0");
	my $response ;
	
	# si formulaire POST
	if ($postData ) {
		foreach my $pair (@{$postData}) {
			my ($pattern,$formValues)=@{$pair};
			if ($url=~/$pattern/) {
				# remplissage et validation
				$response = $ua->post( $url, $formValues );
				my %h=%{$formValues};
				$this->printTrace("Sending data [".(join (",",keys %h))."]\n");
				last;
			}
		}
	} 
	if (!defined($response)) {
		#~ my $req = HTTP::Request->new( GET => $url );
		#~ my $res = $ua->request($req);
		$response = $ua->get( $url);
	}
	if ($response->is_success) {
		$this->printTrace( "$url : ".length($response->content)." characters.\n");
		$response->header("Content-Type") && $this->printTrace( "Type : ".$response->header("Content-Type")."\n");
		$response->header("Location") && $this->printTrace( "Location : ".$response->header("Location")."\n");
		$this->printTrace("\n");
		my $content=$response->content;
		my $charset;
		if ($inputEncoding && $inputEncoding!='bin') {
			$this->printTrace( "Decoding page as $inputEncoding\n");
			$content=decode($inputEncoding,$content);
		} elsif ($response->header("Content-Type")=~/charset=(.*)/) {
			$charset=$1;
			$this->printTrace( "Decoding page as $charset\n");
			$content=decode($charset,$content);
		}
		return ($content,$response->header("Content-Type"),$response->header("Location")); 
	} else {
		$this->printTrace( "Query $url has failed : ".$response->status_line."\n",{warn=>1});
	}
	return "";
}

sub supprTag {
	my $str=shift;
	$str=~ s/<[^>]*>/ /g;
	$str=~ s/\x0D|\x0A/ /g;
	$str=~ s/ +/ /g;
	$str=~s/&nbsp;/ /g;
	$str=~s/&lt;/</g;
	$str=~s/&gt;/>/g;
	$str=~s/&quot;/"/g;
	return $str;
}

#------------------------------------------------------------------------------------------------
END {}

1; 
