<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  version="1.0">
  <xsl:output method="html" />

  <xsl:variable name="start" select="/response/result/@start" />
  <xsl:variable name="presults"
    select="count(//response/lst[@name='highlighting']//lst)" />
  <xsl:variable name="tresults" select="/response/result/@numFound" />
  <xsl:variable name="rows"
    select="//lst[@name='params']/str[@name='rows']" />
  <xsl:variable name="navcount"
    select="floor( ( $tresults - $start ) div $rows)" />
  <xsl:template name="navigator">
    <xsl:param name="count" select="0" />
    <xsl:if test="$count &lt; 10 and $count &lt; $navcount">
      <span>
        <a href="SAPEVENT:004?{$count}">
          <xsl:value-of select="$start + ($count + 1) * $rows + 1" />
        </a>
      </span>
      <xsl:call-template name="navigator">
        <xsl:with-param name="count" select="$count + 1" />
      </xsl:call-template>
    </xsl:if>
  </xsl:template>

  <xsl:template match="/">
    <!-- ABAP Values to be received by program -->
    <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">
      <asx:values>
        <TOTAL_RESULTS>
          <xsl:value-of select="response/result/@numFound" />
        </TOTAL_RESULTS>
        <OFFSET>
          <xsl:value-of select="(response/result/@start)" />
        </OFFSET>
        <PAGE_RESULTS>
          <xsl:value-of select="(count(//response/lst[@name='highlighting']//lst))" />
        </PAGE_RESULTS>
      </asx:values>
    </asx:abap>
    <html>
      <head>
        <LINK href="sr.css" rel="stylesheet" type="text/css" />
      </head>
      <body>
        <xsl:if test="$tresults &gt; 0">
          <p>
            Showing
            <xsl:value-of select="(response/result/@start)+1" />
            to
            <xsl:value-of
              select="(response/result/@start)+(count(//response/lst[@name='highlighting']//lst))" />
            of
            <xsl:value-of select="response/result/@numFound" />
          </p>
        </xsl:if>
        <xsl:if test="$tresults &lt; 1">
          <p>No results returned</p>
        </xsl:if>
        <p>
          <xsl:if test="(response/result/@start) &gt; 0">
            <span>
              <a href="SAPEVENT:002">&lt;&lt; Previous</a>
            </span>
          </xsl:if>

          <xsl:call-template name="navigator" />

          <xsl:if
            test="(response/result/@start)+(count(//response/lst[@name='highlighting']//lst)) &lt; response/result/@numFound">
            <span>
              <a href="SAPEVENT:003">Next &gt;&gt;</a>
            </span>
          </xsl:if>
        </p>
        <xsl:for-each select="response/lst[@name='highlighting']/lst">
          <br />
          <a href="SAPEVENT:001?{@name}">
            <xsl:value-of select="@name" />
          </a>
          <br />
          <xsl:for-each select="arr/str">
            <br />
            <xsl:value-of select="." />
          </xsl:for-each>
          <hr />
        </xsl:for-each>
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>