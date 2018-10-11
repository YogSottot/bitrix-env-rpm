#!/usr/bin/php
<?php

$_SERVER["DOCUMENT_ROOT"] = $argv[1];
$DOCUMENT_ROOT = $_SERVER["DOCUMENT_ROOT"];
define("NO_KEEP_STATISTIC", true);
define("NOT_CHECK_PERMISSIONS",true);
define('BX_NO_ACCELERATOR_RESET', true);
require($_SERVER["DOCUMENT_ROOT"]."/bitrix/modules/main/include/prolog_before.php");

if(!empty($argv[2]) && CModule::IncludeModule('search'))
{
	COption::SetOptionString('search', 'full_text_engine', 'sphinx');
	COption::SetOptionString('search', 'sphinx_connection', '127.0.0.1:9306');
	COption::SetOptionString('search', 'sphinx_index_name', $argv[2]);
	echo "Sphinx search on on site";
}

?>