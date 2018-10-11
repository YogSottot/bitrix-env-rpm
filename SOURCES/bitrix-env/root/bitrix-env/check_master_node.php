<?
$_SERVER["DOCUMENT_ROOT"] = '/home/bitrix/www';
$DOCUMENT_ROOT = $_SERVER["DOCUMENT_ROOT"];
define("LANGUAGE_ID", "en");
define("NO_KEEP_STATISTIC", true);
define("NOT_CHECK_PERMISSIONS",true);
define('BX_NO_ACCELERATOR_RESET', true);
require($_SERVER["DOCUMENT_ROOT"]."/bitrix/modules/main/include/prolog_before.php");

CModule::IncludeModule('cluster');
$mainNode = false;
$slaveNode = false;
$arMaster = array('ID' => 1);
$obCheck = new CClusterDBNodeCheck;
$arCheckList = $obCheck->MainNodeCommon($arMaster);
$mainNode = CheckListHasNoError($arCheckList);

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
