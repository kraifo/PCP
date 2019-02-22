
verbose=1
sourceId='revuegeo'

# 1. paramètres du crawling
targetDir="./data/revuegeo/html" 
url='https://rga.revues.org/'
urlPattern=qr/^https:\/\/rga.revues.org\/\d+/ #liens à parcourir 
maxRecordedPages=2000
resetCrawling=1
limitDepth=3
noFormData=1

#exemple des liens a parcourir: https://www.cairn.info/revue-recherches-en-psychanalyse-2012-2-page-114.htm

#~ blackListUrlPattern=qr//
#~ paginationUrlPattern=qr/lejournal.cnrs.fr\/articles([^\/]|$)/

# 2. paramètres de définition du contenu
contentPattern=qr/<meta name="citation_language" content="(?:fr|en)".*?<div id="text" class="section">(.*?)<\/div>\s*<!-- #text -->/s
namePattern=[qr/rga.revues.org\/(\d+)$/]
nameBase='url'
inputEncoding='utf8'
outputEncoding='utf8'
metadataPatterns=[
	{label=>'analytic.title',base=>'content',search=>qr/<meta name="citation_title" content="(.*?)"/s},
	{label=>'authors',base=>'content',search=>qr/<meta name="citation_authors" content="(.*?)"/s},
	{label=>'date',base=>'content',search=>qr/<meta name="citation_publication_date" content="(.*?)"/s},
	{label=>'publisher',base=>'content',search=>qr/<meta name="citation_publisher" content="(.*?)"/s},
	{label=>'monogr.title',base=>'content',search=>qr/<meta name="citation_journal_title" content="(.*?)"/s},
	{label=>'issue',base=>'content',search=>qr/<meta name="citation_issue" content="(.*?)"/s},
	{label=>'language',base=>'content',search=>qr/<meta name="citation_language" content="(.*?)"/s},
	{label=>'bibl',base=>'content',search=>qr/<div id="quotation" class="section">.*?<p>(.*?)<\/p>/s},
	]
metadataFilePattern=[qr/(.*)/,'$1.meta']

# 3. paramètres d'alignement
#~ alignedUrlTransformationScheme={'en'=>[qr/[.]htm/,'a.htm']}
#~ alignedUrlTransformationScheme={'en'=>[qr/page-(\d+)[.]htm/,'page-".($1+1).".htm']}
sourceLanguage="fr"
alignedUrlWithContextPatterns={en=>qr/<dt>Traduction\(s\) :<\/dt>\s*<dd class="title traduction">\s*<a href="(.*?)">/}
downloadIfAligned=1


#~ ->addSource()

#~ ->runCrawler()


#****************************** cleaning boilerplate html 
inputDir="./data/revuegeo/html"
outputDir="./data/revuegeo/html2"
filePattern=qr/html$/
outputFileName=[qr/[.]html/,'.html']
searchReplacePatterns=[[qr/<[^>]*>Partager<[^>]*>/,""]]
#~ ->findAndReplace({overwriteOutput=>1})


#****************************** converting html to text

inputDir="./data/revuegeo/html"
outputDir="./data/revuegeo/txt"
filePattern=qr/html$/
outputFileName=[qr/[.]html/,'.txt']
fileEncoding="utf8"


#~ ->html2txt({overwriteOutput=>1})
->next()

#****************************** aligning with YASA

# perl runPipeline.pl --function runYasa --param "fileEncoding='CP1252'" "filePattern=qr/(.*)[.]\w\w.txt$/" "languagePattern=qr/[.](\w\w).txt$/" "languages=['en','fr']" "outputFileName=[qr/\w\w.txt\$/,'en-fr.ces']" "inputDir='/home/kraifo/public_html/webAlign/server/php/files/test'" "outputDir='/home/kraifo/public_html/webAlign/server/php/files/test/output'" "inputFormat='txt'" "outputFormat='cesalign'" "overwriteOutput=1" "verbose=1" "radiusAroundAnchor=100"

fileEncoding='raw'
guessEncoding=1
filePattern=qr/(.*)[.]\w\w.txt$/
languagePattern=qr/[.](\w\w).txt/
languages=["en","fr"]
outputFileName=[qr/\w\w.txt$/,"en-fr.tmx"]
outputDir='./data/revuegeo/tmx'
inputFormat='txt'
outputFormat='tmx'
printScore=0
radiusAroundAnchor=100
verbose=1

#~ ->runYasa({overwriteOutput=>1})


#****************************** adding <p> tags
# parameter :
# - noEmptyPara : boolean - if 1, consecutive ends of line will yield only one tag

fileEncoding='utf8'
outputDir="./data/revuegeo/para"
filePattern=qr/txt$/
outputFileName=[qr/(.*)[.]txt$/i,'$1.txt']
noEmptyPara=1
escapeMeta2Entities=1

#~ ->addParaTag({overwriteOutput=>1})
->next()

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


outputDir="./data/revuegeo/tok"
language='fr'
filePattern=qr/fr[.]txt$/
outputFileName=[qr/(.*)[.]txt$/,'$1.tok']
newLineTag=''

#~ ->tokenize({overwriteOutput=>1})

language='en'
filePattern=qr/en[.]txt$/
outputFileName=[qr/(.*)[.]txt$/,'$1.tok']
newLineTag=''

#~ ->tokenize({overwriteOutput=>1})
->next()

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


filePattern=qr/(.*).fr.tok$/
treetaggerLanguage="french-utf8"
outputDir="./data/revuegeo/ttg"
outputFileName=[qr/(.*).tok$/i,'$1.ttg']
tokenize=0
supprSpcTag=1
sentMark="SENT"
addSentTag=1

#~ ->runTreetagger({overwriteOutput=>1})

filePattern=qr/(.*).en.tok$/
treetaggerLanguage="english-utf8"

#~ ->runTreetagger({overwriteOutput=>1})
->next()


#****************************** creating segmented text
inputDir="./data/revuegeo/ttg"
outputDir="./data/revuegeo/seg"
filePattern=qr/ttg$/
outputFileName=[qr/[.]ttg/,'.seg']
searchReplacePatterns=[
	[qr/<(p|s).*>.*\n/,""],
	[qr/(.*)\t.*\t.*\n/,'$1'],
	[qr/<\/p.*>.*\n/,""],
	[qr/<\/s.*>.*\n/,"\n"],
	]
->findAndReplace({overwriteOutput=>0})

#****************************** aligning with LF Aligner
inputDir="./data/revuegeo/seg"
outputDir="./data/revuegeo/tmx"

filePattern=qr/(.*).\w\w.seg$/
languagePattern=qr/(\w\w).seg$/
fileEncoding="utf8"
inputFormat="txt"
outputFormat="tmx"
overwriteOutput=1
verbose=1

->runLFAligner()
->die()

# ****************************** converting to TEI
# applying a template
# parameters :

# - template : string - the template file
# - data : hash ref - data to fill in the template
# - dataFilePattern : [/pattern/,replace] - pattern to transform inputFileName in dataFileName, a file which contains additionnal data (typically a *.meta file)


template='./grm/tei.revue.tpl'
filePattern=qr/(.*).ttg$/
outputDir="./data/revuegeo/tei"
outputFileName=[qr/(.*).ttg$/i,'$1.xml']
dataFilePattern=[qr/ttg\/(.*extract).\w\w[.]ttg/,'html/$1.fr.html.meta']
data={
	'h.title'=>"Corpus Bilingue Revue de recherche en psychanalyse",
	respType=>"Téléchargé en parallèle par",
	respName=>"Olivier Kraif",
	distributor=>"Université Grenoble Alpes",
	pubDate=>"2017",
	samplingDecl=>"full paper",
	segmentation=>"paragraph and sentence level",
	}

->applyTemplate({overwriteOutput=>1})

# ****************************** aligning Texts

inputDir='/home/kraifo/public_html/webAlign/server/php/files/test'
outputDir='/home/kraifo/public_html/webAlign/server/php/files/test/output'

filePattern=qr/(carroll.*).\w\w.txt$/
languagePattern=qr/(\w\w).txt$/
fileEncoding="utf8"
inputFormat="txt"
outputFormat="tmx"
overwriteOutput=1
verbose=1

->runLFAligner()

# ****************************** extracting stats 


inputDir='./data/revuegeo/ttg'
filePattern=qr/(.*)fr.ttg$/
outputDir='./data/revuegeo/stats.fr'
inputFormat="ttg"
outputFormat="csv"
global=1

#~ ->anaText({overwriteOutput=>1})

filePattern=qr/(.*)en.ttg$/
outputDir='./data/revuegeo/stats.en'
inputFormat="ttg"
outputFormat="csv"
global=1

#~ ->anaText({overwriteOutput=>1})
