ABAP Source Search
==================

ABAP source code search using Apache Solr

This project consists of a number of files which you need to manually import in your ABAP system by creating some ABAP programs.

Just follow the easy instructions!

Installation
------------

The solution contains three source files:

  * ZSOLR_ABAPSRC_INDEX.abap
  * ZSOLR_ABAPSRC_SEARCH.abap
  * ZSOLR_ABAPSRC_XSLT.xslt
  
The first two programs must be created as report programs (type 1) on the system.

The third source is an XSL Transformation, which must be created as an XSLT program with transaction XSLT_TOOL.

*NOTE:* It is important to keep the name of the XSLT program as "ZSOLR_ABAPSRC_XSLT", as this is how it is referred to in ZSOLR_ABAPSRC_SEARCH. (In future releases this will be made configurable).

Administration
--------------

Run program ZSOLR_ABAPSRC_INDEX. On the selection screen, you set the URL of the Solr server on your network:

> http://tomcat.example.com:8080/solr

You must save this URL using the "Save Solr URL" button, as this value will then be used by the ZSOLR_ABAPSRC_SEARCH program.

It is recommended to carry out the retrieval and indexing task in the background. For deltas (i.e. incremental changes after the initial extract)
save a variant where you set the attributes of parameters P_UDAT and P_UTIM with the setting "Save field without values" in the variant attributes.
This will ensure that only changes since the last run of the job are exported.

Usage
-----

Run program ZSOLR_ABAPSRC_SEARCH. You can read up on the Solr search syntax at wiki.apache.org/solr/.

For example, the following query will look for the word "todo" in all abap programs, but exclude certain generated code modules.

> todo AND NOT "CODE COMPOSER ANNOTATION" AND NOT "check controller fields"

(Tip: save search results like these as report variants for repeated use).

From the result list, you can navigate directly to the source module and page between results.