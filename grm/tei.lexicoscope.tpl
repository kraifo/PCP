<?xml version="1.0" encoding="utf8"?>
<teiCorpus xmlns="http://www.tei-c.org/ns/1.0">
	<teiHeader>
		<fileDesc>
			<titleStmt>
				<title value="{{title}}"/>
				<author value="{{author}}"/>
				<translation source_language="{{sourceLanguage}}" source_title="{{sourceTitle}}" translator="{{translator}}" date="{{translationDate}}" />
			</titleStmt>
			<publicationStmt>
				<publisher value="{{publisher}}" />
				<pubPlace value="{{pubPlace}}" />
				<pubDate value="{{pubDate}}" />
				<pubURL value="{{pubUrl}}" />
				<pubNumeric value="" />
			</publicationStmt>
		</fileDesc>
		<profileDesc>
			<langUsage>
				<language ident="{{language}}" />
			</langUsage>
			<textDesc type="{{type}}" genre="{{genre}}" theme="{{theme}}" />
		</profileDesc>
	</teiHeader>
	<text>
		<body>
			{{content}}
		</body>
	</text>
</teiCorpus>
