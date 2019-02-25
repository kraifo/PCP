
verbose=1
sourceId='journalcnrs'
targetDir="./data/lejournalcnrs/html" 
url='https://lejournal.cnrs.fr/articles'
urlPattern=qr/^https:..lejournal.cnrs.fr.articles/ #liens a parcourir 
blackListUrlPattern=qr/tid=\d/
paginationUrlPattern=qr/lejournal.cnrs.fr\/articles([^\/]|$)/
resetCrawling=0
limitDepth=5
#noFormData=1
downloadIfAligned=1

contentPattern=qr/(<h1 class="node-title">(.*?)<\/h1>.*?<div class="article-contenu.*?">(.*?)<!-- FLAGS -->)/s
#exemple des liens a parcourir: https://lejournal.cnrs.fr/articles/lextraordinaire-sens-de-lorientation-des-fourmis
namePattern=[qr/.*articles.(.*)/,'$1'] 

nameBase='url' #'content'
inputEncoding='utf8'
outputEncoding='utf8'
metadataPatterns=[
	{label=>'title',base=>'content',search=>qr/<h1 class="node-title">(.*?)<\/h1>/s},
	{label=>'author',base=>'content',search=>qr/<a href="\/auteurs\/.*?" class="node node-.*? entityreference">(.*?)<\/a>/s},
	{label=>'date',base=>'content',search=>qr/<span class="date-display-single">(.*?)<\/span>/},
	{label=>'theme',base=>'content',search=>qr/<div class="thematiques-taxonomy.*?"><a href=".*?">(.*?)<\/a><\/div><\/div>/},
	]
metadataFilePattern=[qr/(.*)/,'$1.meta']

maxRecordedPages=10000
sourceLanguage="fr"
alignedLinkPatterns={"en"=>qr/cnrs\/images\/gb.svg/}

#->addSource()
#->runCrawler()



#****************************** cleaning boilerplate html 
inputDir="./data/lejournalcnrs/html"
outputDir="./data/lejournalcnrs/html2"
filePattern=qr/html$/
outputFileName=[qr/[.]html/,'.html']
searchReplacePatterns=[
	[qr/<div class="niveau-2">.*?<\/div><\/div>\s*<\/div>/s,""],
	[qr/<a class="see-footnote".*?<\/a>/,""],
	[qr/<div class="image.*?<p>/s,"<p>"],
	[qr/<p><div  class="asset-wrapper asset aid-\d\d\d\d asset-video">.*?<\/p>/s,""],
	[qr/<div class="footnotes-wrapper">.*?<!-- FLAGS -->/s,""],
	[qr/<iframe.*?<p> <\/p>\s*<p>.*?<\/p>/s,""]
	]

->findAndReplace({overwriteOutput=>0})

#****************************** converting html to text

inputDir="./data/lejournalcnrs/html2"
outputDir="./data/lejournalcnrs/txt"
filePattern=qr/html$/
outputFileName=[qr/[.]html/,'.txt']
fileEncoding="utf8"


->html2txt({overwriteOutput=>0})
->next()

#****************************** adding <p> tags
# parameter :
# - noEmptyPara : boolean - if 1, consecutive ends of line will yield only one tag

outputDir="./data/lejournalcnrs/para"
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


outputDir="./data/lejournalcnrs/tok"
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
outputDir="./data/lejournalcnrs/ttg"
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
outputDir="./data/lejournalcnrs/tei"
outputFileName=[qr/(.*).ttg$/i,'$1.xml']
dataFilePattern=[qr/ttg\/(.*extract.\w\w)[.]ttg/,'html/$1.html.meta']
data={
	'h.title'=>"Corpus Bilingue Le Journal du CNRS",
	respType=>"Téléchargé en parallèle par",
	respName=>"Dorian Bellanger",
	distributor=>"Université Grenoble Alpes",
	pubDate=>"2018",
	samplingDecl=>"full paper",
	segmentation=>"paragraph and sentence level",
	}

->applyTemplate({overwriteOutput=>1})


# ****************************** extracting stats 


inputDir='./data/lejournalcnrs/ttg'
filePattern=qr/(.*)fr.ttg$/
outputDir='./data/lejournalcnrs/stats.fr'
inputFormat="ttg"
outputFormat="csv"
global=1

->anaText({overwriteOutput=>1})

filePattern=qr/(.*)en.ttg$/
outputDir='./data/lejournalcnrs/stats.en'
inputFormat="ttg"
outputFormat="csv"
global=1

->anaText({overwriteOutput=>1})
