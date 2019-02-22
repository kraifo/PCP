# Perl Corpus Processor Toolkit


## 1. Introduction

PCP is a toolkit for implementing pipelines on text corpora. The philosophy of PCP is to use Perl's regular expression language at all levels of the pipeline: for text crawling on the Web, file naming definition, directory naming, implementation of cascading find and replace, tokenization, sentence segmentation, etc. It should be noted that by using capture groups and back references, this regular expression language is much more powerful than a simple regular language.

## 2. Installation
One should first install the last distribution of Perl 5 (for Windows, use Strawberry Perl or Active Perl) from here : https://www.perl.org/get.html
Then unzip the full archive where you want on your disk, in a directory called PCP.
Then if you want to use treetagger, download it from here : 
http://www.cis.uni-muenchen.de/~schmid/tools/TreeTagger/
and copy the complete directory in the /path/to/PCP/lib/treetagger directory (or create a symbolic link to this directory). You may also copy other plugins, as LF aligner or Stanford Parser, CoreNLP by copying them in the /path/to/PCP/lib directory.

## 3. Getting started

The pipelines are files ending with .pl extension (as Perl file, even if they are not Perl scripts: anyway they can be edited using syntactic coloration). To execute them, one runs the script runPipeline.pl. For a pipeline named myPipe.pl, one should write:
perl runPipeline.pl myPipe.pl

For each command, a series of parameters are listed, followed by their value expressed in Perl syntax. The execution of a function, corresponding to a processing step, is carried out with the prefix -> at the beginning of the line :
->function()

In the Perl syntax, we will use the following conventions:
- the strings between simple quote: 'example'
- regular expressions between /.../ and prefixed by qr : qr/(.*)\.xml/
- the lists between brackets [...] : ['example1','example2']
- the hashes between braces {...} : {' key1' => ' value1',' key2' => ' value2' }
For example, the following parameters are used to configure the runAlineaLite() function, which is intended for bilingual alignment:

```perl
    \# comments are possible (and recommended!), prefixed by #
    inputDirL1='data/multi/en/EUconst'
    inputDirL2='data/multi/fr/EUconst'
    outputDir='data/multi/en-fr'
    filePattern=qr/(.*)\.xml/
    outputFileName=[
    	qr/\.xml/,
	    '.en-fr.txt'
    	] # a parameter can be expressed on several lines provided that the following lines are indented

    inputFormat='xml'
    outputFormat='tmx'
    fileEncoding='utf8'
    verbose=1
    options='--segmentation_tag s --tokenization_tag w'

    ->RunAlineaLite({overwriteOutput=>1}) # running the function
```

Any parameter definition is stored in the pipeline. It is therefore not necessary to specify stable parameters, such as windows, verbose or even fileEncoding, for each call. 
If you want to use a parameter only once, without memorizing it, you just have to add it directly to the arguments of the function, as here {overwriteOutput=>1}

## 4. General parameters
At each step of a processing chain, care should be taken to define an output directory different from the input directory. It may be useful to prefix the directory names with the step number in order to clarify the sequence of functions. For example, for a processing chain consisting of downloading HTML files, then reformatting them into TXT, then segmenting them into sentences, and finally putting them in XML-TEI format, we can create the following directories:
```
    1_html
    2_txt
    3_seg
    4_tei
```
At each step, we generally define: 

- an input directory (string, inputDir parameter)
- an output directory (string, outputDir parameter)
- the pattern of the files to be processed in the input directory (regex, filePattern parameter)
- the file encoding (string, fileEncoding parameter)
- the naming scheme of the output files (string or list, outputFileName parameter). If the name of the output file is constant (i.e. if it does not depend on the input file), then a simple string can be defined. But most of the time, the output file name is the result of a transformation of the input file name. We therefore apply a scheme of the type [qr/searchedPattern/,'replacementChain']. In this scheme, we can use groups of captures (with brackets) and references to captured strings ($1,$2, etc.). For example: 
```perl
    [qr//,'']		# identity : the output file has the same name
    [qr/(.*)/,'$1'] 	# identity : the output file has the same name
    [qr/$/,'.txt'] 	# addition of the suffix .txt at the end of the name
    [qr/[.](\w\w\w)$/,'.utf8.$1']	# adding the suffix utf8 before the file extension
```
Here are all the parameters related to the definition of file and directory names:

- inputDir : string - default value ='...' (e.g. '/the/dir/where/the/input/files/are/stored/')
- outputDir : string - default value=inputDir (e.g. '/the/dir/where/the/output/files/are/stored/')
- filePattern: pattern - default value=qr/.*/ (e.g. qr/txt$/ to process all *.txt files)
- fileEncoding: string - default value='utf8'
- outputFileName: [pattern,'string'] - transformation scheme of the input file name to obtain the output file name.
- outputDirPattern: [pattern,'string'] - transformation scheme to change the input directory name into the output directory name (useful when performing a recursive path of the input directories).
- recursion: boolean - default value=1 (recursive path of subdirectories)
- processLinks : default value=0 (if 1, symbolic links will be processed during recursion - be careful with infinite loops!!!! )
- overwriteOutput: boolean - default value=0 (if the output file already exists, and the parameter is set to 0, the step will be ignored)
- outputBackupExtension: string ("no"|"bak"|"bakN") if the output file already exists and we have overwriteOutput=1, then 3 possible values : 
	* "no" -> no backup 
	* "bak"-> the previous version is saved with the suffix .bak 
	* "bakN"-> previous versions are saved with incrementally numbered extensions e. g. .bak0, .bak1, .bak2, etc.)

Other parameters are used to manage the writing of logs and execution traces:
 
- verbose : boolean - 1 to display on STDOUT execution trace
- printLog : boolean - 1 to print the execution trace in a log file 
- logFileName : string - the LOG file name - may contains timestamp variable e.g. 'extractCollocation.pl.$year-$mon-$mday.$hour-$min-$sec.log'
- appendLog : boolean - if 1, the log file named perlNLPToolkit.pl.log is open in append mode

Finally, for a Toolkit execution under windows, it is important to set the windows parameter to 1:

- windows : boolean - 1 for the Windows OS
