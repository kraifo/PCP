
# perl runPipeline.pl --function runYasa --param "fileEncoding='CP1252'" "filePattern=qr/(.*)[.]\w\w.txt$/" "languagePattern=qr/[.](\w\w).txt$/" "languages=['en','fr']" "outputFileName=[qr/\w\w.txt\$/,'en-fr.ces']" "inputDir='/home/kraifo/public_html/webAlign/server/php/files/test'" "outputDir='/home/kraifo/public_html/webAlign/server/php/files/test/output'" "inputFormat='txt'" "outputFormat='cesalign'" "overwriteOutput=1" "verbose=1" "radiusAroundAnchor=100"

inputDir="./data/Bovary/src"
outputDir="./data/Bovary/tmx"

fileEncoding='utf8'
filePattern=qr/(.*)[.]\w\w.txt$/
languagePattern=qr/[.](\w\w)[.]\w+$/
languages=["fr","es","en","it"]
#alignFileName='$commonName.$l1-$l2.$ext'

inputFormat='txt'
outputFormats=['tmx']
printScore=0
radiusAroundAnchor=100
verbose=1

->runYasa({overwriteOutput=>1})
