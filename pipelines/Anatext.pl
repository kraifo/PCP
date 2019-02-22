
#****************************** converting pdf to text

language='fr'
inputDir="./data/Bovary/src"
outputDir="./data/Bovary/report"
filePattern=qr/\d.fr.txt$/,
outputFileName=[qr/(.*)[.]txt$/i,'$1.txt.occ.csv']
coocspan=3
repeatedSegmentsMaxLength=7
catPattern=[qr/(.*?):.*/,'$1']
useSimplifiedTagset=1
tagsetName='tagsetTreetagger'
labelLanguage="fr"
vocIncreaseStep=100
refCorpus=""
#refCorpora : {name=>string*} - a list of filenames of various corpora with various frequency ranges 
features2record={'VER'=>["cond","futu","impf","infi","pper","pres","simp","subi","subp"]}
global=0


->anaText({overwriteOutput=>1})
