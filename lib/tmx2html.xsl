<?xml version="1.0" ?>

<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:fo="http://www.w3.org/1999/XSL/Format"
                version='1.0'>



<xsl:output method="html"

  encoding="utf8"

  indent="yes" />




<xsl:template match="header"> 
</xsl:template>

<xsl:template match="body">

	<html>
		<head>
			<title>TMX file</title>
			<link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.10.15/css/jquery.dataTables.min.css" />
			<script type="text/javascript" language="javascript" src="https://code.jquery.com/jquery-1.12.4.js"></script>
			<script type="text/javascript" language="javascript" src="https://cdn.datatables.net/1.10.15/js/jquery.dataTables.min.js"></script>
			<style>
				body {
					margin-left:50px;
					margin-right:50px;
				}
			</style>
		</head>
		<body>
			<h1>TMX Bi-text displayed with XSLT</h1>
			<table id="bitext" class="display" cellspacing="0" width="100%">
				<thead>
					<xsl:apply-templates select="tu[1]" />
				</thead>
				
				<tbody>
					<xsl:for-each select="tu">
						<tr>
							<td class="id">
								<xsl:value-of select="@tuid" />
							</td>
								
							<xsl:for-each select="tuv">

								<td>
									<xsl:apply-templates select="seg" />
								</td>

							</xsl:for-each> 
						</tr>
					</xsl:for-each>
		
				</tbody>

			</table>
		</body>
		<script>
			$(document).ready( function () {
				 $('#bitext').DataTable(
					{
					"aLengthMenu": [[-1,10,50,100],["All",10,50, 100]],
					"column": [ { "width": "5%" }, { "width": "45%" }, { "width": "45%" }]
					},
				 );
				
			});		
		</script>
	</html>

</xsl:template>

<xsl:template match="tu">

				<tr>
					<th>
						Num
					</th>
					<xsl:for-each select="tuv">
						<th>
							<xsl:value-of select="@xml:lang" />
						</th>
					</xsl:for-each> 
				</tr>
				
</xsl:template>




<xsl:template match="prop">

    <xsl:value-of select="." />

</xsl:template>



<xsl:template match="seg">

    <xsl:value-of select="." />

</xsl:template>



</xsl:stylesheet>
