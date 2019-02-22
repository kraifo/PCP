 
sourceId='langages'
targetDir="./data/langages2/pdf"
url='http://www.persee.fr/collection/lgge'
urlPattern=qr/^http:..www.persee.fr\/.*lgge_0458-726x_2001\w*$/
otherLinkPattern=qr/<form action="(http:..www.persee.fr.docAsPDF.lgge_0458-726x_2001\w+.pdf)" method="post" id="pdf-download-form">/
url2download=qr/lgge_0458-726x_2001.*.pdf$/
namePattern=[qr/.*lgge_0458-726x_(.*).pdf.*/,'Langages.$1.pdf']
nameBase='url'
inputEncoding='bin'
outputEncoding='bin'
metadataPatterns=[
	{
	label=>'date',
	base=>'url',
	search=>qr/.*lgge_0458-726x_(\d\d\d\d).*/
	}]
metadataFilePattern=[qr/(.*)/,'$1.meta']
resetCrawling=1
limitDepth=4
maxRecordedPages=50
verbose=1

->addSource()

->runCrawler()
->die()
#****************************** converting pdf to text

inputDir="./data/langages2/pdf"
outputDir="./data/langages2/txt"
filePattern=qr/pdf$/,
outputFileName=[qr/(.*)[.]pdf$/i,'$1.pdf.txt']
externalCommandArguments='$inputFileName $outputFileName'
externalCommand='./lib/xpdf/pdftotext.exe'
externalCommand='./lib/xpdf/pdftotext_linux64'

->runExternalCommand({overwriteOutput=>1})
->die()

#****************************** adding <p> tags
# parameter :
# - noEmptyPara : boolean - if 1, consecutive ends of line will yield only one tag

inputDir="./data/langages2/txt"
outputDir="./data/langages2/para"
filePattern=qr/pdf.txt$/
outputFileName=[qr/(.*)[.]txt$/i,'$1.para.txt']
fileEncoding='iso-8859-1'
noEmptyPara=1

->addParaTag({overwriteOutput=>1})

#****************************** tokenize raw txt files
# Parameters :
# - language : string - the language of texts (in order to load corresponding grammar and dics) - default = "fr"
# - dicPath : string - the path to the directory that contains the dictionaries - default='./dics'
# - grmPath : string - the path to the directory that contains the grammar rules - default='./grm'
# - tokSeparator : string - the separator char that will be inserted between every token - default="\n",
# - printType : boolean - if true, the type of the token is printed - default=0,
# -	typeSeparator : string - the character separating the token and the type tag - default="\t",
# -	newLineTag : string - the string that reprensents a newline char - default="<p>",
# - defaultRules : the set of default rules that are used to tokenize without a specific (see PerlNLPToolKit.pm for more details on the rules)


language='fr'
inputDir='./data/langages2/para'
outputDir='./data/langages2/tok'
fileEncoding="iso-8859-1"
filePattern=qr/para[.]txt$/
outputFileName=[qr/(.*)[.]txt$/,'$1.txt.tok']
newLineTag=''

->tokenize({overwriteOutput=>1})
->next()


#****************************** converting to utf8

inputDir='./data/langages2/tok'
outputDir='./data/langages2/tok-utf8'
inputEncoding="iso-8859-1"
outputEncoding="utf8"
filePattern=qr/para[.]txt[.]tok$/
outputFileName=[qr/(.*)$/,'$1.utf8']

->convertEncoding({overwriteOutput=>1})

#****************************** runing xip


filePattern=qr/(.*).txt.tok.utf8$/
fileEncoding="utf8"
inputDir='./data/langages/tok-utf8'
outputDir='./data/langages/xip'
outputFileName=[qr/(.*)$/i,'$1.xip']
tokenize=0


#~ ->runXip({overwriteOutput=>1})

# ****************************** tagging files
# Parameters :
# - treetaggerPath : string - treetagger install path - must be set for any installation 
# - treetaggerOptions : string - treetagger options - default="-token -lemma -sgml -no-unknown"
# - treetaggerLanguage : string - treetagger language - default="french-utf8" (the parameters file must be treetaggerPath/lib/treetaggerLanguage.par)
# - treetaggerAppName : string - treetagger binary executable - default='tree-tagger' (for windows 'treetagger.exe')
# - tokenize : boolean - if false, no tokenization is done
# - treetaggerTokenizer : string - the name of the tokenizer, wich must be installed in treetaggerPath/cmd - default='tokenize.perl'
# - treetaggerUTF8Tokenizer : string - the name of the tokenizer for utf8 files, wich must be installed in treetaggerPath/cmd - default='utf8-tokenize.perl'
# - windows : boolean - 1 for Windows OS



filePattern=qr/(.*).txt.tok.utf8$/
fileEncoding="utf8"
inputDir='./data/langages2/tok-utf8'
outputDir='./data/langages2/ttg'
outputFileName=[qr/(.*)$/i,'$1.ttg']
tokenize=0

->runTreetagger({overwriteOutput=>1})


# treetagger postprocessing -> add the spaces encoded by the tokenisation stage <spc value=' ' /> to the corresponding surface form (column one)
# Parameters :
# - addSentTag : boolean - if true add sentence tags <s id='sid'>...</s> around each sentence

->next()

addSentTag=1
outputDir='./data/langages2/ttg2'
outputFileName=[qr/(.*)$/i,'$1']


->postTreetagger({overwriteOutput=>1})

# ****************************** converting to TEI
# applying a template
# parameters :

# - template : string - the template file
# - data : hash ref - data to fill in the template
# - dataFilePattern : [/pattern/,replace] - pattern to transform inputFileName in dataFileName, a file which contains additionnal data (typically a *.meta file)


template='./grm/tei.tpl'
inputDir='./data/langages2/ttg2'
outputDir='./data/langages2/tei'
outputFileName=[qr/(.*)$/i,'$1.xml']
data={	'h.title'=>'Exemple de corpus - Revue Langages 2000',respName=>'O. Kraif',pubPlace=>'Paris',publisher=>'Armand Colin','monogr.title'=>'Revue Langages'}
dataFilePattern=[qr/ttg2\/(.*)[.]pdf.*/,'pdf/$1.pdf.meta']


->applyTemplate({overwriteOutput=>1})

# ****************************** searching expressions
# Parameters :
# - language : string - default value='fr',			
# - outputConcord : boolean - if 1, concord file is created, adding 'concord' to outputFilename
# - outputConcordFormat : string ('kwik'|'xml') - the format of ouput concord file
# - outputIndex : if 1, index file is created, adding 'index' to outputFilename
# - outputStat : if 1, stat file is created, adding 'stat' to outputFilename
# - span : integer or string (number|'sent') - the size of the right and left contextual window
# - spanUnit : string ('char'|'token') - the span size unit
# - queries : list ref - the query list ('DET ADJ NOM' or '%faire NOM PRE' or '%avoir <>{,4} peur')
# - queryFile : string - a file with one query per line
# - countBy : string ('query'|'lemma'|'form'|'cat') - indicates which feature is used to represent expressions in statistics
# - groupByFile : boolean - all the results are grouped independtly for each files. If 0, all the data are merged independently of the source file
# - sortBy : list ref - the list of sorting keys e.g. ['F','expr']	- keys are ('F'|'F<'|'expr'|'right'|'left'|'pos') 'F<' means  by ascending order of frequency for counted entries, 'F' means  by descending order of frequency, 'left' mean by the end of the left context


language='fr'
inputDir='./data/langages2/ttg2'
filePattern=qr/.*/
outputDir='./data/langages2/searchResult'
outputConcord=1
outputStat=1
outputConcordFormat="kwik"
queries=['DET ADJ NOM','%faire NOM']
countBy='form'
sortBy=['F','expr']
outputFileName=[qr/(.*)/i,'$1.DET_ADJ_NOM']
groupByFile=0


#~ ->search({overwriteOutput=>1})

#***************************** compute collocations
# parameters
# - coocspan : integer - indicates the size (in word) of the sliding window
# - insideSent : boolean - indicates whether the cooccurrence span is limited by sentence boundary (=1) or not (=0)
# - countBy : string ('lemma'|'form'|'cat'|'form_cat'|'lemma_cat') - indicates which feature is used to represent expressions in statistics
# - coocTable : string - the name of the collocation table
# - orderSensitive : boolean - if 1, cooccurrence of c1..c2 is not identical to c2..c1 - if 0, c1..c2 = c2..c1 (which means that the real cooc span is 2*span-1 because it represents [-span...+span])
# - toLowerCase : boolean - if 1, every entry is lowercased in the table

# The fields that may be in the output are : c1, c2, f1, f2, f12, log-like, pmi, t-score, z-score
# - c1Pattern : pattern - to filter the form of collocate 1 (e.g. qr/.*_NOM/) to get noun, if countBy = 'lemma_cat' in extractCollocation() ouput
# - c2Pattern : pattern - to filter the form of collocate 2 (e.g. qr/.*_NOM/) to get noun, if countBy = 'lemma_cat' in extractCollocation() ouput
# - filterBy : list ref - define criteria to filter results lines - ['f12>10','f1>4','log-like>=10.83'] - 
# - orderBy : ['l1','ll'] - define the multiple sorting key for the results
# - displayCol : ['c1','ll','c2'] - the column that have to be in the output


inputDir='./data/langages2/ttg2'
outputDir='./data/langages2/searchResult'
filePattern=qr/ttg$/
coocTable="lemma.span4.dat"
countBy='lemma_cat'
coocspan=4
toLowercase=1


#~ ->extractCoocTable({overwriteOutput=>1})


c1Pattern=qr/.*_N.*/
c2Pattern=qr/.*_V.*/
outputFileName=[qr/(.*)/,'$1.cooc.csv']
filterBy=['log-like>10.83']
orderBy=['log-like>','c1','c2']
displayColumns=['c1','c2','log-like']


#~ ->displayCollocations({overwriteOutput=>1})
