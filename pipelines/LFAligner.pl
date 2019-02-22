# ligne de commande : perl runPipeline.pl --function runJAM --param "inputDir='/home/kraifo/public_html/webAlign/server/php/files/test'" "outputDir='/home/kraifo/public_html/webAlign/server/php/files/test/output'" "filePattern=qr/(.*).\w\w.txt$/" "languagePattern=qr/(\w\w).\w\w\w$/" "fileEncoding='CP1252'" "inputFormat='txt'" "outputFormat='tmx'" "overwriteOutput=1" "logDir='/home/kraifo/public_html/webAlign/server/php/files/test/output'"


# exécution de LF Aligner

inputDir='../data/Alice/txt'
outputDir='../data/Alice/tmx'

filePattern=qr/(.*).\w\w.txt$/
languagePattern=qr/(\w\w).txt$/
fileEncoding="utf8"
inputFormat="txt"
outputFormat="tmx"
overwriteOutput=1
verbose=1

->runLFAligner()

filePattern=qr/(carroll.*).\w\w.ces$/
languagePattern=qr/(\w\w).ces$/
fileEncoding="utf8"
inputFormat="ces"
outputFormat="tmx"
overwriteOutput=1
verbose=1

->runJAM()

