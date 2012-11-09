var showFile = function(txt) {
	$("source").style.display = "";
	$("source").innerHTML="<pre class='first-line: 1;brush: objc'>"+txt+"</pre>";
	
	SyntaxHighlighter.defaults['toolbar'] = false;
	SyntaxHighlighter.highlight();
	
	return;
}

var setMessage = function(message) {
	$("message").style.display = "";
	$("message").innerHTML = message.escapeHTML();
	$("source").style.display = "none";
}

var test=function(txt) {
	SyntaxHighlighter.defaults['toolbar'] = false;
	SyntaxHighlighter.highlight();
	
	return;
}
