<?
$_SERVER["DOCUMENT_ROOT"] = '/home/bitrix/www';
$DOCUMENT_ROOT = $_SERVER["DOCUMENT_ROOT"];

define("LANGUAGE_ID", "en");
define("NO_KEEP_STATISTIC", true);
define("NOT_CHECK_PERMISSIONS",true);
#define('BX_NO_ACCELERATOR_RESET', true);
require($_SERVER["DOCUMENT_ROOT"]."/bitrix/modules/main/include/prolog_before.php");
require('/root/bitrix-env/tmp/db_connect.php');

if(!CModule::IncludeModule('cluster'))
{
	echo "Web cluster module is not installed
";
}

$arMaster = array('ID' => 1);
$mainNode = false;
$slaveNode = false;
$obCheck = new CClusterDBNodeCheck;
$arCheckList = $obCheck->MainNodeCommon($arMaster);
$mainNode = CheckListHasNoError($arCheckList);

$DB = $obCheck->SlaveNodeConnection($dbHost, $dbName, 'root', $dbPasswd);
if(is_object($DB))
{
	$arCheckList = $obCheck->SlaveNodeCommon($DB);
	$slaveNode = CheckListHasNoError($arCheckList);
}

function CheckListHasNoError($arList)
{
	foreach($arList as $rec)
	{
		if($rec["IS_OK"] != true)
		{
			echo $rec['MESSAGE']."
";
		}
	}
}
?>
