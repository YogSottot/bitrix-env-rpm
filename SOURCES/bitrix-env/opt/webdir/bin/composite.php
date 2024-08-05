#!/usr/bin/php
<?php
$options = getopt("f:");

if (!isset($options["f"]) || strlen($options["f"]) < 1 || !file_exists($options["f"]))
{
    fputs(STDERR, "File Not Found\n");
    exit(1);
}

$arHTMLPagesOptions = array();
include($options["f"]);

fputs(STDOUT, json_encode($arHTMLPagesOptions));
exit(0);
?>
