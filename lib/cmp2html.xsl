<?xml version="1.0" encoding="utf8" ?>

<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:fo="http://www.w3.org/1999/XSL/Format"
                version='1.0'>
<xsl:output method="html"
  encoding="utf8"
  indent="yes" />

<html>
	<head>
		<meta charset='utf8'/>
		<style>
			common {
				color:#000000;
			}
			v1 {
				color:#800000;
				text-decoration:none;
			}
			v2 {
				color:#000080;
			}
		</style>
		<script src="https://ajax.googleapis.com/ajax/libs/jquery/3.3.1/jquery.min.js"></script>
	</head>
	<body>
		<button onclick="$('v1').fadeIn();$('v2').fadeOut()">v1</button>
		<button onclick="$('v2').fadeIn();$('v1').fadeOut()">v2</button>
		<button onclick="$('v1').fadeIn();$('v2').fadeIn()">Diff</button>
		<br/>

		<xsl:value-of select="cmp">

	</html>
</body>
