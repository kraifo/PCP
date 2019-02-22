<?xml version="1.0" encoding="utf8"?>
<TEI.2 xmlns="http://www.tei-c.org/ns/1.0">

	<teiHeader>
		<fileDesc>
			<titleStmt >
				<title value="{{title}}"/>
				<author value="{{author}}"/>
			</titleStmt>
			<publicationStmt >
				<publisher  value="{{publisher}}"/>
				<pubPlace  value="{{pubPlace}}"/>
				<pubDate  value="{{date}}"/>
				<pubURL  value=""/>
				<pubNumeric  value=""/>
			</publicationStmt>
			<formatSource  value="doc"/>
		</fileDesc>
		<profileDesc >
			<langUsage >
				<language ident="{{language}}"/>
			</langUsage>
			<textDesc theme="{{theme}}" type="{{type}}" />
			<annotation value=""/>
			<wordsNumber value=""/>
		</profileDesc>
	</teiHeader>
	<text>
		<body>
			{{content}}
		</body>
	</text>
</TEI.2>
