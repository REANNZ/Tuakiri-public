<?xml version="1.0" encoding="UTF-8"?>
<xsl:transform version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata">
  <xsl:output method="xml" indent="yes" />

  <xsl:template match="/md:EntityDescriptor">
    <xsl:copy>
      <!-- copy all attributes of this node -->
      <xsl:copy-of select="@*" />

      <!-- and from the child elements, copy only IDPSSODescriptor -->
      <xsl:copy-of select="md:IDPSSODescriptor" />
    </xsl:copy>
  </xsl:template>
</xsl:transform>
