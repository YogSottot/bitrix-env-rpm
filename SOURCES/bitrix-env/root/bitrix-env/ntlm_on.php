<?

$_SERVER["DOCUMENT_ROOT"] = '/home/bitrix/www/';
$DOCUMENT_ROOT = $_SERVER["DOCUMENT_ROOT"];
define("NO_KEEP_STATISTIC", true);
define("NOT_CHECK_PERMISSIONS",true);
define('BX_NO_ACCELERATOR_RESET', true);
require($_SERVER["DOCUMENT_ROOT"]."/bitrix/modules/main/include/prolog_before.php");

if(!CModule::IncludeModule('ldap'))
	return false;


$ipMask = COption::GetOptionString("ldap", "bitrixvm_auth_net", false);
CLdapUtil::SetBitrixVMAuthSupport(true, $ipMask);

echo '

Ntlm auth on;

';

?>