*&---------------------------------------------------------------------*
*& Report  ZSOLR_ABAPSRC_SEARCH
*& Frontend for ABAP source code search using index created on an
*& Apache Solr server by program ZSOLR_ABAPSRC_INDEX
*&---------------------------------------------------------------------*
*& Author: Martin Ceronio, martin.ceronio@infosize.co.za
*& Distributed in the Public Domain without warranty of any kind
*&---------------------------------------------------------------------*

report zsolr_abapsrc_search.

selection-screen begin of line.
parameters: p_query type string lower case.
selection-screen pushbutton 50(10) sbut user-command srch.
selection-screen end of line.
selection-screen comment /1(60) info.
parameters: p_url    type string lower case no-display.

data: client type ref to if_http_client.
data: request type ref to if_http_request.
data: response type ref to if_http_response.
data: msg type string.
data: htm type string.
data: url type string.
data: q type string.                 "Query string
data: qtmpl type string.             "Query template
data: start(6) type n.               "Start offset of search
data: rows(6) type n value 10.       "Number of results per page
data: scheme type string.
data: hostport type string.          "Host and port of search server
data: path type string.
data: index_available type boole_d.

data: total_results type i,          "Total number of results of search
      offset type i,                 "Offset of search results
      page_results type i.           "Results on current page

data: html_tab type htmltable.
data: length type i.

data events type cntl_simple_events.
data event type  cntl_simple_event.

data: container type ref to cl_gui_docking_container.
data: htmlc type ref to cl_gui_html_viewer.

data: code type i.
data: reason type string.

*----------------------------------------------------------------------*
*       CLASS lc_hevt DEFINITION
*----------------------------------------------------------------------*
class lc_hevt definition.
  public section.
    methods: sapevt_handler for event sapevent of cl_gui_html_viewer
      importing
        action
        frame
        getdata
        postdata
        query_table.
endclass.                    "lc_hevt DEFINITION

*----------------------------------------------------------------------*
*       CLASS lc_hevt IMPLEMENTATION
*----------------------------------------------------------------------*
class lc_hevt implementation.
  method sapevt_handler.
    case action.
      when '001'. "Result Link Clicked
        data: prog type progname.
        prog = getdata.
        call function 'EDITOR_PROGRAM'
          exporting
            display     = 'X'
*           LINE        = '000001'
*           OFFSET      = '00'
            program     = prog
*           TOPLINE     = '000000'
          exceptions
            application = 1
            others      = 2.
        if sy-subrc <> 0.
          message 'Error when calling up source editor' type 'I'.
        endif.
      when '002'. "Previous Link Clicked
        subtract rows from start.
        if start lt 0.
          start = 0.
        endif.
        perform do_search.
      when '003'. "Next Link Clicked
        add rows to start.
        if start > total_results.
          start = total_results. "Or just total_results - 1?
        endif.
        perform do_search.
      when '004'. "
        start = start + rows * ( getdata + 1 ).
        perform do_search.
    endcase.
  endmethod.                    "sapevt_handler
endclass.                    "lc_hevt IMPLEMENTATION

data: lr_sevt type ref to lc_hevt.

*&---------------------------------------------------------------------*
*&      Form  execute_query
*&---------------------------------------------------------------------*
form execute_query using p_request.

  clear: code, reason.

* Set up HTTP request
  request->set_method( if_http_entity=>co_request_method_get ).

* Execute request
  call method client->send
    exceptions
      http_communication_failure = 1
      http_invalid_state         = 2
      http_processing_failed     = 3
      http_invalid_timeout       = 4
      others                     = 5.
  if sy-subrc <> 0.
    return.
  endif.

* Process response
  call method client->receive
    exceptions
      http_communication_failure = 1
      http_invalid_state         = 2
      http_processing_failed     = 3
      others                     = 4.
  if sy-subrc <> 0.
    return.
  endif.

* Check status of response; issue error if not successful (200)
  call method response->get_status
    importing
      code   = code
      reason = reason.

  if code ne 200.
    sy-subrc = 7.
    return.
  else.

  endif.

endform.                    "execute_query

*&---------------------------------------------------------------------*
*&      Form  initialize_client
*&---------------------------------------------------------------------*
form initialize_client.

  call method cl_http_client=>create_by_url
    exporting
      url                = p_url
    importing
      client             = client
    exceptions
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
  import p_url from database indx(za) id 'ZSOLR_URL'.
  if sy-subrc ne 0.
    message 'Please configure Solr URL first' type 'E'.
  else.
    call function 'SWLWP_URI_PARSE'
      exporting
        uri         = p_url
      importing
        scheme      = scheme
        hostport    = hostport
        abs_path    = path
      exceptions
        uri_no_path = 1
        others      = 2.
    if sy-subrc <> 0.
      message 'Unable to parse URL for Solr server' type 'E'.
    endif.
* Build URL to server for initial connection
    concatenate scheme '://' hostport into url.
* Build Query template
    concatenate
*      path '/select?q=text:#{QUERY}&start=#{START}&rows=#{ROWS}&hl=true&hl.fl=text&fl=id'
      path '/select?q=text:#{QUERY}&start=#{START}&rows=#{ROWS}&hl=true&hl.fl=text&fl=id&hl.snippets=8'
      into qtmpl.
  endif.
  sbut = 'Search'.
  perform initialize_client.
* TODO - do an initial call (ping) to the server
* For now we just show a green light if the client could be instantiated
  perform execute_query using '/admin/ping'.
  if code = 200.
    concatenate '@5B@' hostport into info separated by space.
    index_available = abap_true.
  else.
    index_available = abap_false.
    concatenate '@5C@' hostport into info separated by space.
  endif.

at selection-screen.
  if sy-ucomm = 'SRCH' or sy-ucomm = space.
    if index_available = abap_true.
      start = 0. "Reset the offset counter
      perform do_search.
    endif.
  endif.

at selection-screen output.
* Take Execute function away from report selection screen
  perform insert_into_excl(rsdbrunt) using 'ONLI'.

* Set up the result HTML view container first time around
  if container is not bound.
    create object container
      exporting
        side                        = cl_gui_docking_container=>dock_at_bottom
        ratio                       = 90
      exceptions
        cntl_error                  = 1
        cntl_system_error           = 2
        create_error                = 3
        lifetime_error              = 4
        lifetime_dynpro_dynpro_link = 5
        others                      = 6.
    if sy-subrc <> 0.
      message id sy-msgid type sy-msgty number sy-msgno
                 with sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    endif.
    create object htmlc
      exporting
        parent             = container
      exceptions
        cntl_error         = 1
        cntl_install_error = 2
        dp_install_error   = 3
        dp_error           = 4
        others             = 5.
    if sy-subrc <> 0.
      message id sy-msgid type sy-msgty number sy-msgno
                 with sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    endif.
* Set up event handler for clicks
    create object lr_sevt.
    set handler lr_sevt->sapevt_handler for htmlc.
    event-eventid = 001.
    event-appl_event = 'X'.
    append event to events.
    call method htmlc->set_registered_events
      exporting
        events                    = events
      exceptions
        cntl_error                = 1
        cntl_system_error         = 2
        illegal_event_combination = 3
        others                    = 4.
    if sy-subrc <> 0.
      message id sy-msgid type sy-msgty number sy-msgno
                 with sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    endif.
* Set the CSS for highlighting
    clear html_tab.
    append 'em { font-weight: bold; background-color: yellow; }' to html_tab.
    append 'span { padding: 2px; }' to html_tab.
    append 'html { font-family: sans-serif; }' to html_tab.
    call method htmlc->load_data
      exporting
        url                    = 'sr.css' "Highlighting for em
        subtype                = 'css'
      changing
        data_table             = html_tab
      exceptions
        dp_invalid_parameter   = 1
        dp_error_general       = 2
        cntl_error             = 3
        html_syntax_notcorrect = 4
        others                 = 5.
    if sy-subrc <> 0.
* Can ignore this; highlighting will not be as great
    endif.
  endif.
*&---------------------------------------------------------------------*
*&      Form  DO_SEARCH
*&---------------------------------------------------------------------*
form do_search .
  q = qtmpl.
  replace '#{QUERY}' with p_query into q.
  replace '#{START}' with start into q.
  replace '#{ROWS}' with rows into q.
* Set request URI
  call method cl_http_utility=>set_request_uri
    exporting
      request = request
      uri     = q.
  perform execute_query using q.

* Check for errors
  if sy-subrc between 1 and 6.
    message 'Error contacting server' type 'I'.
    return.
  elseif sy-subrc = 7.
    msg = code.
    concatenate msg reason into msg separated by space.
    message msg type 'I'.
    return.
  endif.

* Process results if the call was successful
  clear html_tab.
  msg = response->get_cdata( ).

  try.
* Convert result XML into HTML to display
      call transformation zsolr_abapsrc_xslt source xml msg result xml htm.

* From the resulting HTML(XML) we deserialize the specific values that
* tell us about the search results
      call transformation id source xml htm result
        total_results = total_results
        offset = offset
        page_results = page_results.
* Having done that, we need to strip out everything until the start of <html>,
* a little dirty workaround for getting the values with the response
      find first occurrence of '<html>' in htm
        match offset length.
      shift htm left by length places.

* The emphasis tags are escaped by the transformation, so put them back
      replace all occurrences of '&lt;em&gt;' in htm with '<em>'.
      replace all occurrences of '&lt;/em&gt;' in htm with '</em>'.

* Convert HTML to a table to load into HTML viewer
      length = strlen( htm ).
      while length > 132.
        append htm(132) to html_tab.
        shift htm left by 132 places.
        subtract 132 from length.
      endwhile.
      if length > 0.
        append htm to html_tab.
      endif.

* Load the HTML result into the HTML viewer
      data: aurl(2048) type c.
      call method htmlc->load_data
        importing
          assigned_url           = aurl
        changing
          data_table             = html_tab
        exceptions
          dp_invalid_parameter   = 1
          dp_error_general       = 2
          cntl_error             = 3
          html_syntax_notcorrect = 4
          others                 = 5.
      if sy-subrc <> 0.
        message id sy-msgid type sy-msgty number sy-msgno
                   with sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
      endif.

* Display result to user
      call method htmlc->show_data
        exporting
          url                    = aurl
        exceptions
          cntl_error             = 1
          cnht_error_not_allowed = 2
          cnht_error_parameter   = 3
          dp_error_general       = 4
          others                 = 5.
      if sy-subrc <> 0.
        message id sy-msgid type sy-msgty number sy-msgno
                   with sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
      endif.
    catch cx_transformation_error.
      message 'Error processing response from server' type 'I'.
  endtry.
endform.                    " DO_SEARCH