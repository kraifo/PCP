
verbose=1
latency=0.5
sourceId='revuepsy'
targetDir="./data/revuepsy/html" 
url='https://www.cairn.info/revue-research-in-psychoanalysis.htm'
urlPattern=qr/^https:..www.cairn.info.revue-recherches-en-psychanalyse-201\d-\d+(-page-\d+)?.htm/ #liens à parcourir 
#exemple des liens a parcourir: https://www.cairn.info/revue-recherches-en-psychanalyse-2012-2-page-114.htm


correspondingUrlPattern={"en"=>qr/<div class="article greybox_hover" id="REP_[^"]*?">\s*?<div class="authors">\s*?<span class="author">\s+<a class="yellow" href="([^"]*)">.*?<a\s*href="(?<href1>[^"]*?)".*?<div class="article greybox_hover" id="REP_[^"]*?">\s*?<div class="authors">\s*?<span class="author">\s+<a class="yellow" href="(\1)">.*?<a\s*href="(?<href2>[^"]*?)"/}

#~ blackListUrlPattern=qr//
#~ paginationUrlPattern=qr/lejournal.cnrs.fr\/articles([^\/]|$)/
resetCrawling=1
limitDepth=3
#noFormData=1
downloadIfAligned=1
alignedUrlTransformationScheme={'en'=>[qr/[.]htm/,'a.htm']}
#~ alignedUrlTransformationScheme={'en'=>[qr/page-(\d+)[.]htm/,'page-".($1+1).".htm']}
contentPattern=qr/<!-- DEBUT DU CONTENU DE L'ARTICLE -->(.*?)<!-- FIN DU CONTENU DE L'ARTICLE -->/s
namePattern=[qr/www.cairn.info.revue-recherches-en-psychanalyse-(.*).htm/]
nameBase='url'

inputEncoding='utf8'
outputEncoding='utf8'
metadataPatterns=[
	{label=>'analytic.title',base=>'content',search=>qr/<!--field: Titre-->(.*?)<!--field: -->/s},
	{label=>'authors',base=>'content',search=>qr/<!--field: Auteur-->(.*?)<!--field: -->/s},
	{label=>'year',base=>'content',search=>qr/<meta name="citation_year" content="(.*?)">/s},
	{label=>'date',base=>'content',search=>qr/<meta name="citation_online_date" content="(.*?)">/s},
	{label=>'firstPage',base=>'content',search=>qr/<meta name="citation_firstpage" content="(.*?)">/s},
	{label=>'lastPage',base=>'content',search=>qr/<meta name="citation_lastpage" content="(.*?)">/s},
	{label=>'publisher',base=>'content',search=>qr/<meta name="citation_publisher" content="(.*?)">/s},
	{label=>'monogr.title',base=>'content',search=>qr/<meta name="citation_journal_title" content="(.*?)">/s},
	{label=>'volume',base=>'content',search=>qr/<meta name="citation_volume" content="(.*?)">/s},
	{label=>'language',base=>'content',search=>qr/<meta name="citation_language" content="(.*?)">/s},
	{label=>'languageId',base=>'content',search=>qr/<meta name="citation_language" content="(.*?)">/s},
	{label=>'bibl',base=>'content',search=>qr/<span class="blue_milk" id="apa">(.*?)<\/span>\s*<a/s},
	]
metadataFilePattern=[qr/(.*)/,'$1.meta']

maxRecordedPages=2000
sourceLanguage="fr"

->addSource()

#~ ->runCrawler()



#****************************** cleaning boilerplate html 
inputDir="./data/revuepsy/html"
outputDir="./data/revuepsy/html2"
filePattern=qr/html$/
outputFileName=[qr/[.]html/,'.html']
searchReplacePatterns=[[qr/<[^>]*>Partager<[^>]*>/,""]]
#~ ->findAndReplace({overwriteOutput=>1})


#****************************** converting html to text

inputDir="./data/revuepsy/html"
outputDir="./data/revuepsy/txt"
filePattern=qr/html$/
outputFileName=[qr/[.]html/,'.txt']
fileEncoding="utf8"


#~ ->html2txt({overwriteOutput=>1})
->next()

#****************************** adding <p> tags
# parameter :
# - noEmptyPara : boolean - if 1, consecutive ends of line will yield only one tag


outputDir="./data/revuepsy/para"
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


outputDir="./data/revuepsy/tok"
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
outputDir="./data/revuepsy/ttg"
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

# ****************************** converting to TEI
# applying a template
# parameters :

# - template : string - the template file
# - data : hash ref - data to fill in the template
# - dataFilePattern : [/pattern/,replace] - pattern to transform inputFileName in dataFileName, a file which contains additionnal data (typically a *.meta file)


template='./grm/tei.revue.tpl'
filePattern=qr/(.*).ttg$/
outputDir="./data/revuepsy/tei"
outputFileName=[qr/(.*).ttg$/i,'$1.xml']
dataFilePattern=[qr/ttg\/(.*extract.\w\w)[.]ttg/,'html/$1.html.meta']
data={
	'h.title'=>"Corpus Bilingue Revue de recherche en psychanalyse",
	respType=>"Téléchargé en parallèle par",
	respName=>"Olivier Kraif",
	distributor=>"Université Grenoble Alpes",
	pubDate=>"2017",
	samplingDecl=>"full paper",
	segmentation=>"paragraph and sentence level",
	}

#~ ->applyTemplate({overwriteOutput=>1})


# ****************************** extracting stats 


inputDir='./data/revuepsy/ttg'
filePattern=qr/(.*)fr.ttg$/
outputDir='./data/revuepsy/stats.fr'
inputFormat="ttg"
outputFormat="csv"
global=1

->anaText({overwriteOutput=>1})

filePattern=qr/(.*)en.ttg$/
outputDir='./data/revuepsy/stats.en'
inputFormat="ttg"
outputFormat="csv"
global=1

->anaText({overwriteOutput=>1})
