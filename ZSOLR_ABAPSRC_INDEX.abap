*&---------------------------------------------------------------------*
*& Report  ZSOLR_ABAPSRC_INDEX
*& Retrieves source code for ABAP programs and sends to Apache Solr
*& service for indexing
*&---------------------------------------------------------------------*
*& Author: Martin Ceronio, martin.ceronio@infosize.co.za
*& Distributed in the Public Domain without warranty of any kind
*&---------------------------------------------------------------------*

report zsolr_abapsrc_index line-size 255 no standard page heading.

data: gs_reposrc type reposrc.
data: gt_reposrc type sorted table of reposrc with unique key progname r3state.

data: gt_src type string_table.
data: gv_src type string.

data: client type ref to if_http_client.
data: request type ref to if_http_request.
data: response type ref to if_http_response.
data: src type string.
data: doc type string.
data: add type string.
data: prg type string.
data: msg type string.
data: cur type cursor.
data: url type string.
data: err_count type i.
data: pkg_count type i.
data: obj_count type i.
data: line(6) type n.

data: code type i.
data: reason type string.

parameters: p_pkgsz type i default 30 obligatory.
parameters: p_compk type i default 10 obligatory.
parameters: p_url type string memory id zsol obligatory lower case.
parameters: p_maxer type char5 default '50' obligatory.
selection-screen skip.
parameters: p_init type flag as checkbox default space.
parameters: p_lines type flag as checkbox default 'X'.
select-options: s_progs for gs_reposrc-progname.
parameters: p_resum type progname.
selection-screen skip.
parameters: p_delta type flag as checkbox.
parameters: p_udat type rdir_udate.
parameters: p_utime type ddtime.
selection-screen: skip,
                  pushbutton /1(20) didx user-command didx,
                  pushbutton 30(20) oidx user-command oidx,
                  skip,
                  pushbutton /1(20) surl user-command surl.

define log.
  if sy-batch = 'X'.
* To prevent program from stopping, reduce severity of errors etc.
    message &2 type &1.
  else.
    write: / &1, &2.
  endif.
* Update error count and stop the program if the maximum errors are reached
  if &1 = 'E' or &1 = 'W'.
    add 1 to err_count.
    if err_count ge p_maxer.
      write: / 'Maximum Errors Reached - Exiting'.
      leave program.
    endif.
  endif.
end-of-definition.

* Delete contents of index
if p_init = 'X'.
  perform delete_index.
  if sy-subrc = 0.
    log 'I' 'Index deleted successfully'.
  endif.
endif.

* Record timestamp for deltas
export date from sy-datum time from sy-uzeit to database indx(za) id 'ZSOLR_TIMESTAMP'.

if p_delta = abap_true.
  write: / 'Indexing deltas since', p_udat, p_utime.
endif.

do.

* TODO: Make selection dynamic using a dynamic where
  if p_delta = abap_true.
    select * from reposrc
       into table gt_reposrc
       up to p_pkgsz rows
      where progname in s_progs
     and progname > p_resum "Last program processed
     and ( ( udat gt p_udat or ( udat = p_udat and utime >= p_utime ) )
          or ( cdat ge p_udat ) )
     and r3state = 'A'
     order by progname.
  else.
    select * from reposrc
       into table gt_reposrc
       up to p_pkgsz rows
     where progname in s_progs
     and progname > p_resum "Last program processed
     and r3state = 'A'
     order by progname.
  endif.

* Exit DO block when there is nothing more to select
  if sy-subrc ne 0.
    exit.
  endif.

  add = '<add>'.

* Process selected programs
  loop at gt_reposrc into gs_reposrc.
    read report gs_reposrc-progname into gt_src.

* Concatenate program source into single string
    clear src.
    loop at gt_src into gv_src.
      if p_lines = 'X'.
        line = sy-tabix.
        concatenate line gv_src into gv_src separated by space.
      endif.
      concatenate src gv_src cl_abap_char_utilities=>horizontal_tab into src.
    endloop.

* Some programs (including this one) would cause the indexer to vomit because it contains a ]]>
* sequence that messes up the XML CDATA
    replace all occurrences of ']]>' in src with ']]]]><![CDATA[>'.
* This clever solution compliments of:
* http://stackoverflow.com/questions/223652/is-there-a-way-to-escape-a-cdata-end-token-in-xml

* Set command string for index
    doc = '<doc><field name="id">#{PROGNAME}</field><field name="text"><![CDATA[ #{SOURCE} ]]></field></doc>'.
    prg = gs_reposrc-progname.
    replace '#{PROGNAME}' with prg into doc.
    replace '#{SOURCE}'   with src into doc.

    concatenate add doc into add.

    add 1 to obj_count.

  endloop.

  p_resum = prg. "Next package will be selected after this program

  concatenate add '</add>' into add.

* Update index
  perform exec_request using add changing code reason.
  if sy-subrc ne 0.
    msg = strlen( add ).
    concatenate 'Size of last request:' msg into msg separated by space.
    log 'I' msg.
  endif.
  add 1 to pkg_count.

* Commit after package
  if pkg_count ge p_compk.
*    perform exec_request using '<commit/>' changing code reason.
    perform exec_request using '<commit waitSearcher="false"/>' changing code reason.
    if sy-subrc = 0.
      concatenate 'Index updated. Last program =' prg into msg separated by space.
    endif.
    export p_resum to database indx(za) id 'ZSOLR_LASTPROG'.
    log 'I' msg.
    pkg_count = 0.
  endif.

enddo.

* Optimize index
perform exec_request using '<optimize waitSearcher="false"/>' changing code reason.
if sy-subrc = 0.
  log 'I' 'Index optimization started.'.
endif.

* Clean up
CALL METHOD client->close
  EXCEPTIONS
    http_invalid_state = 1
    others             = 2.
if sy-subrc <> 0.
  log 'I' 'Problem closing client connection - not serious'.
endif.

log 'I' 'Indexing completed.'.

* After completion of successful index, make the last program for resume blank
delete from database indx(za) id 'ZSOLR_LASTPROG'.

* Write summary statistics
write: / 'Objects processed :', obj_count.
write: / 'Errors encountered:', err_count.

*&---------------------------------------------------------------------*
*&      Form  delete_index
*&---------------------------------------------------------------------*
form delete_index.
  perform exec_request using '<delete><query>*:*</query></delete> ' changing code reason.
  if sy-subrc ne 0.
    exit.
  endif.
  perform exec_request using '<commit/>' changing code reason.
  if sy-subrc ne 0.
    exit.
  endif.
endform.                    "delete_index

*&---------------------------------------------------------------------*
*&      Form  exec_request
*&---------------------------------------------------------------------*
form exec_request using body changing code type i reason type string.

  if client is not bound.
    perform initialize_client.
  endif.

* Set up HTTP request
  request->set_method( if_http_entity=>co_request_method_post ).
  request->set_cdata( body ).

  data: extract type text100.

* Execute request
  CALL METHOD client->send
    EXCEPTIONS
      http_communication_failure = 1
      http_invalid_state         = 2
      http_processing_failed     = 3
      http_invalid_timeout       = 4
      others                     = 5.
  if sy-subrc <> 0.
    extract = body.
    msg = sy-subrc.
    concatenate 'SY-SUBRC =' msg 'Request:' extract into msg separated by space.
    log 'W' msg.
    sy-subrc = 4.
    return.
  endif.

* Process response
  CALL METHOD client->receive
    EXCEPTIONS
      http_communication_failure = 1
      http_invalid_state         = 2
      http_processing_failed     = 3
      others                     = 4.
  if sy-subrc <> 0.
    extract = body.
    msg = sy-subrc.
    concatenate 'SY-SUBRC =' msg 'Request:' extract into msg separated by space.
    log 'I' msg.
    sy-subrc = 4.
    return.
  endif.

* Check status of response; issue error if not successful (200)
  CALL METHOD response->get_status
    IMPORTING
      code   = code
      reason = reason.

  if code ne 200.
    extract = request->get_cdata( ).
    msg = code.
    concatenate 'HTTP Code =' msg reason 'Request:' extract into msg separated by space.
    log 'I' msg.
    sy-subrc = 4.
    return.
  endif.

endform.                    "exec_request

*&---------------------------------------------------------------------*
*&      Form  initialize_client
*&---------------------------------------------------------------------*
form initialize_client.
  concatenate p_url '/update' into url.

  CALL METHOD cl_http_client=>create_by_url
    EXPORTING
      url                = url
    IMPORTING
      client             = client
    EXCEPTIONS
      argument_not_found = 1
      plugin_not_active  = 2
      internal_error     = 3
      others             = 4.
  if sy-subrc <> 0.
    msg = sy-subrc.
    concatenate 'Unable to create client; sy-subrc =' msg into msg separated by space.
    message msg type 'I'.
    leave program.
  endif.

  request = client->request.
  response = client->response.
endform.                    "exec_request

initialization.
* Set report screen parameter labels
* (THIS IS NOT GOOD ABAP PRACTICE)
  %_p_pkgsz_%_app_%-text = 'Package Size'.
  %_p_maxer_%_app_%-text = 'Max. Errs before stopping'.
  %_p_init_%_app_%-text = 'Delete index before starting'.
  %_p_url_%_app_%-text = 'Solr URL (no trailing /)'.
  %_p_compk_%_app_%-text = 'Packages in a commit'.
  %_p_lines_%_app_%-text = 'Include line numbers in source'.
  %_s_progs_%_app_%-text = 'Set of code modules to index'.
  %_p_resum_%_app_%-text = 'Resume after program:'.
  %_p_delta_%_app_%-text = 'Only deltas since:'.
  %_p_udat_%_app_%-text = 'Prog. changed since Date/Time'.
  %_p_utime_%_app_%-text = ''.

* Set button texts
  didx = '@11@ Delete Index'.
  oidx = '@37@ Optimize Index'.
  surl = '@45@ Save Solr URL'.

load-of-program.
* Default values of previous indexings etc.
  import p_resum from database indx(za) id 'ZSOLR_LASTPROG'.
  import p_url from database indx(za) id 'ZSOLR_URL'.
  import date to p_udat time to p_utime from database indx(za) id 'ZSOLR_TIMESTAMP'.

at selection-screen.
  case sy-ucomm.
    when 'DIDX'.
      message 'Warning - Index will be deleted' type 'W'.
      perform delete_index.
      if sy-subrc = 0.
        message 'Index deleted successfully' type 'I'.
      else.
        message 'Error deleting index' type 'E'.
      endif.
    when 'OIDX'.
* Optimize index
      perform exec_request using '<optimize waitSearcher="false"/>' changing code reason.
      if sy-subrc = 0.
        message 'Index optimization started.' type 'I'.
      else.
        message 'Error optimizing index' type 'E'.
      endif.
    when 'SURL'.
* Save the Solr URL
      export p_url to database indx(za) id 'ZSOLR_URL'.
      if sy-subrc = 0.
        message 'Solr URL Saved' type 'I'.
      endif.
  endcase.