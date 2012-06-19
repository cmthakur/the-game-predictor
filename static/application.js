$(function() {

  // Prepare our Variables
  var
    History = window.History,
    $ = window.jQuery,
    document = window.document;

  // Check to see if History.js is enabled for our Browser
  if ( !History.enabled ) {
    return false;
  }



  $(".submit_prediction").on("click", function(event) {
    var that = $(this);
    that.attr("disabled", "disabled");
    that.attr("value", "Submitting...");
    var form = that.parents("form");
    var selected_option = form.find("input:checked")
    if(selected_option.length == 1){
      var data_string = 'prediction='+selected_option.val();
      $.ajax({
        type: "POST",
        url: form.attr("action"),
        data: data_string,
        success: function(data) {
          euro_data = data;
          that.removeAttr("disabled");
          if(data['result'] != undefined){
            var prediction_div = form.parents(".prediction");
            prediction_div.find("span.prediction_message").html(data['result']);
            prediction_div.find("a.prediction_link").html("Change");
            prediction_div.find(".modal").modal("hide");
          }else {
            form.find(".alert").html(data['error']).show();
          }
        }
      });
    }else {
      form.find(".alert").html("You GOTs to select one of the results").show();
    }
    event.preventDefault();
    return false;
  });


  $("a[data-remote]").on("click", function(event){
    var that = $(this),
        url = that.attr('href'),
        title = that.attr('title');


    // Continue as normal for cmd clicks etc
    if ( event.which == 2 || event.metaKey ) { return true; }

    // Push into history
    History.pushState(null, title, url);

    event.preventDefault();
    return false;
  });

  if($("#today").length > 0){
    $('html, body').animate({ scrollTop: $('#today').offset().top }, 'slow');
  }


  highlight_current_user_row = function(){
    var user_table_td = $(".leaderboard tr#user_" + current_user_id + "_points td:first");
    if (user_table_td.length > 0){
      user_table_td.append("<i class='icon-hand-right'></i>");
    }
  }

  highlight_current_user_row();

  $(window).bind('statechange',function(){
    var State = History.getState(),
        url = State.url;

    $("#dummy_modal .modal").modal("show");

    $.ajax({
      type: "GET",
      url: url,
      success: function(data){
        $('.content').html(data);
        $("#dummy_modal .modal").modal("hide");
        highlight_current_user_row();
      },
      error: function(jqXHR, textStatus, errorThrown){
        document.location.href = url;
        return false;
      }
    });

  });

});