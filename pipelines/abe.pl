windows=0
verbose=1
sourceId='abe'
targetDir="./data/abe/html"
url='http://journals.openedition.org/abe/'
urlPattern=qr/http:..journals.openedition.org.abe.\d+$/

resetCrawling=1
limitDepth=3
downloadIfAligned=1
alignedUrlWithContextPatterns={en=>qr/<link title=".*?" type="text\/html" rel="alternate" hreflang="en" href="(.*?)"/}
# alignedUrlTransformationScheme={'en'=>[qr/(http:.*\d+)/,'$1?lang=en']}
contentPattern=qr/<meta http-equiv="Content-language" content="(?:fr|en)" \/>.*<!-- #widgets -->(.*)<\/div><!-- .text wResizable -->/s
namePattern=[qr/<title>(.*?)<\/title>/]
nameBase='content'
inputEncoding='utf8'
outputEncoding='utf8'
metadataPatterns=[
	{label=>'authors',base=>'content',search=>qr/<meta name="citation_authors" content="(.*?)"-->/s},
	{label=>'publicationDate',base=>'content',search=>qr/<meta name="citation_publication_date" content="(.*?)"/s},
	{label=>'date',base=>'content',search=>qr/<meta name="citation_online_date" content="(.*?)"/s},
	{label=>'publisher',base=>'content',search=>qr/<meta name="citation_publisher" content="(.*?)"/s},
	{label=>'volume',base=>'content',search=>qr/<meta name="citation_issue" content="(.*?)"/s},
	{label=>'language',base=>'content',search=>qr/<meta name="citation_language" content="(.*?)"/s},
	{label=>'languageId',base=>'content',search=>qr/<meta name="citation_language" content="(.*?)"/s},
	{label=>'bibl',base=>'content',search=>qr/<div id="quotation" class="section">.*?<p>(.*?)<\/p>/s},
	]
metadataFilePattern=[qr/(.*)/,'$1.meta']

maxRecordedPages=10000
sourceLanguage="fr"

#->addSource()
#->runCrawler()


#****************************** cleaning boilerplate html 
inputDir="./data/abe/html"
outputDir="./data/abe/html2"
filePattern=qr/html$/
outputFileName=[qr/[.]html/,'.html']
searchReplacePatterns=[
	[qr/(<span class="paranumber">\d*?<\/span>)/,'$1 '],
	[qr/<div class="textIcon">.*?<\/p>\s*<\/div>/s,""],
	[qr/<div class="textIcon">.*?<\/a><\/div>\s*<\/div>/s,""],          
	[qr/<span class="num">.*?<\/span>/,""],
	[qr/<ul class="sidenotes">.*?<\/ul>/s,""],
	[qr/<a class="footnotecall".*?<\/a>/,""]
	]

->findAndReplace({overwriteOutput=>0})

#****************************** converting html to text

inputDir="./data/abe/html2"
outputDir="./data/abe/txt"
filePattern=qr/html$/
outputFileName=[qr/[.]html/,'.txt']
fileEncoding="utf8"


->html2txt({overwriteOutput=>0})
->next()

#****************************** adding <p> tags
# parameter :
# - noEmptyPara : boolean - if 1, consecutive ends of line will yield only one tag

outputDir="./data/abe/para"
filePattern=qr/txt$/
outputFileName=[qr/(.*)[.]txt$/i,'$1.txt']
noEmptyPara=1
escapeMeta2Entities=1

->addParaTag({overwriteOutput=>1})
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


outputDir="./data/abe/tok"
language='fr'
filePattern=qr/fr[.]txt$/
outputFileName=[qr/(.*)[.]txt$/,'$1.tok']
newLineTag=''

->tokenize({overwriteOutput=>1})

language='en'
filePattern=qr/en[.]txt$/
outputFileName=[qr/(.*)[.]txt$/,'$1.tok']
newLineTag=''

->tokenize({overwriteOutput=>1})
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
outputDir="./data/abe/ttg"
outputFileName=[qr/(.*).tok$/i,'$1.ttg']
tokenize=0
supprSpcTag=1
sentMark="SENT"
addSentTag=1

->runTreetagger({overwriteOutput=>1})

filePattern=qr/(.*).en.tok$/
treetaggerLanguage="english-utf8"

->runTreetagger({overwriteOutput=>1})
->next()

# ****************************** converting to TEI
# applying a template
# parameters :

# - template : string - the template file
# - data : hash ref - data to fill in the template
# - dataFilePattern : [/pattern/,replace] - pattern to transform inputFileName in dataFileName, a file which contains additionnal data (typically a *.meta file)


template='./grm/tei.revue.tpl'
filePattern=qr/(.*).ttg$/
outputDir="./data/abe/tei"
outputFileName=[qr/(.*).ttg$/i,'$1.xml']
dataFilePattern=[qr/ttg\/(.*extract.\w\w)[.]ttg/,'html/$1.html.meta']
data={
	'h.title'=>"Corpus Bilingue Revue Architecture Beyond EUrope",
	respType=>"Téléchargé en parallèle par",
	respName=>"Dorian Bellanger",
	distributor=>"Université Grenoble Alpes",
	pubDate=>"2018",
	samplingDecl=>"full paper",
	segmentation=>"paragraph and sentence level",
	}

->applyTemplate({overwriteOutput=>1})


# ****************************** extracting stats 


inputDir='./data/abe/ttg'
filePattern=qr/(.*)fr.ttg$/
outputDir='./data/abe/stats.fr'
inputFormat="ttg"
outputFormat="csv"
global=1

->anaText({overwriteOutput=>1})

filePattern=qr/(.*)en.ttg$/
outputDir='./data/abe/stats.en'
inputFormat="ttg"
outputFormat="csv"
global=1

->anaText({overwriteOutput=>1})