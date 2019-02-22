<?xml version="1.0" encoding="utf8"?>
<TEI xmlns="http://www.tei-c.org/ns/1.0">
	<teiHeader>
		<fileDesc>
			<titleStmt>
				<h.title>{{h.title}}</h.title>
				<respStmt>
					<respType>{{respType}}</respType>
					<respName>{{respName}}</respName>
				</respStmt>
			</titleStmt>
			<sourceDesc>
				<bibl>
					{{bibl}}
				</bibl>
			</sourceDesc>
		</fileDesc>
		<encodingDesc>
			<samplingDecl>
				{{samplingDecl}}
			</samplingDecl>
			<editorialDecl>
				<conformance>TEI P5	</conformance>
				<correction status="medium" method="silent"></correction>
				<quotation marks="none" form="std">	</quotation>
				<segmentation>
					{{segmentation}}
				</segmentation>
			</editorialDecl>
			<tagsDecl>
			</tagsDecl>
		</encodingDesc>    
		<profileDesc>
			<langUsage>
				<language id="{{languageID}}" iso639="{{languageID}}">{{language}}</language>
			</langUsage>
		</profileDesc>
	</teiHeader>
	<text>
		<body>
			{{content}}
		</body>
	</text>
</TEI>
