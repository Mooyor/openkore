#########################################################################
#  OpenKore - Packet sending
#  This module contains functions for sending packets to the server.
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#
#  $Revision: 6687 $
#  $Id: kRO.pm 6687 2009-04-19 19:04:25Z technologyguild $
########################################################################
# Korea (kRO)
# The majority of private servers use eAthena, this is a clone of kRO

package Network::Send::kRO::Sakexe_0;

use strict;
use Network::Send::kRO ();
use base qw(Network::Send::kRO);

use Log qw(message warning error debug);
use I18N qw(stringToBytes);
use Utils qw(getTickCount getHex getCoordString);

# TODO: maybe we should try to not use globals in here at all but instead pass them on?
use Globals qw($accountID $sessionID $sessionID2 $accountSex $char $charID %config %guild @chars $masterServer $syncSync $net);

sub version {
	return 5;
}

sub new {
	my ($class) = @_;
	return $class->SUPER::new(@_);
}

# 0x0064,55
# NOTE: we support private servers that alter the packetswitch with: $masterServer->{masterLogin_packet}
# NOTE: we support private server that alter the version number by passing on $version
sub sendMasterLogin {
	my ($self, $username, $password, $master_version, $version) = @_;
	my $msg = pack('v V a24 a24 C', hex($masterServer->{masterLogin_packet}) || 0x0064, $version || version(), $username, $password, $master_version);
	$self->sendToServer($msg);
}

# 0x0065,17
# TODO: move 0273 and 0275 to appropriate Sakexe version
sub sendGameLogin {
	my ($self, $accountID, $sessionID, $sessionID2, $sex) = @_;
	my $msg = pack("v a4 a4 a4 x2 C", hex($masterServer->{gameLogin_packet}) || 0x0065, $accountID, $sessionID, $sessionID2, $sex);
	if (hex($masterServer->{gameLogin_packet}) == 0x0273 || hex($masterServer->{gameLogin_packet}) == 0x0275) {
		my ($serv) = $masterServer->{ip} =~ /\d+\.\d+\.\d+\.(\d+)/;
		$msg .= pack("x16 C x3", $serv);
	}
	$self->sendToServer($msg);
	debug "Sent sendGameLogin\n", "sendPacket", 2;
}

# 0x0066,6
sub sendCharLogin {
	my ($self, $char) = @_;
	my $msg = pack('v C', 0x0066, $char);
	$self->sendToServer($msg);
}

# 0x0067,37
sub sendCharCreate {
	my ($self, $slot, $name, $str, $agi, $vit, $int, $dex, $luk, $hair_style, $hair_color) = @_;
	$hair_color ||= 1;

	my $msg = pack('v a24 C7 v2', 0x0067, stringToBytes($name), $str, $agi, $vit, $int, $dex, $luk, $slot, $hair_color, $hair_style);
	$self->sendToServer($msg);
}

# 0x0068,46
sub sendCharDelete {
	my ($self, $charID, $email) = @_;
	my $msg = pack('v a4 a40', 0x0068, $charID, stringToBytes($email));
	$self->sendToServer($msg);
}

# 0x0072,19,wanttoconnection,2:6:10:14:18
sub sendMapLogin {
	my ($self, $accountID, $charID, $sessionID, $sex) = @_;
	$sex = 0 if ($sex > 1 || $sex < 0); # Sex can only be 0 (female) or 1 (male)
	my $msg = pack('v a4 a4 a4 V C', 0x0072, $accountID, $charID, $sessionID, getTickCount(), $sex);
	$self->sendToServer($msg);
}

# 0x007d,2,loadendack,0
sub sendMapLoaded {
	$_[0]->sendToServer(pack('v', 0x007D));
	debug "Sending Map Loaded\n", "sendPacket";
	Plugins::callHook('packet/sendMapLoaded');
}

# 0x007e,6,ticksend,2
sub sendSync {
	my ($self, $initialSync) = @_;
	# XKore mode 1 lets the client take care of syncing.
	return if ($self->{net}->version == 1);

	my $msg = pack('v V', 0x007E, getTickCount());
	$self->sendToServer($msg);
	debug "Sent Sync\n", "sendPacket", 2;
}

# 0x0085,5,walktoxy,2
sub sendMove {
	my $self = shift;
	my $x = int scalar shift;
	my $y = int scalar shift;
	my $msg = pack('v a3', 0x0085, getCoordString($x, $y, 1));
	$self->sendToServer($msg);
	debug "Sent move to: $x, $y\n", "sendPacket", 2;
}

# 0x0089,7,actionrequest,2:6
sub sendAction { # flag: 0 attack (once), 7 attack (continuous), 2 sit, 3 stand
	my ($self, $monID, $flag) = @_;

	my %args;
	$args{monID} = $monID;
	$args{flag} = $flag;
	# eventually we'll trow this hooking out so...
	Plugins::callHook('packet_pre/sendAttack', \%args) if ($flag == 0 || $flag == 7);
	Plugins::callHook('packet_pre/sendSit', \%args) if ($flag == 2 || $flag == 3);
	if ($args{return}) {
		$self->sendToServer($args{msg});
		return;
	}

	my $msg = pack('v a4 C', 0x0089, $monID, $flag);
	$self->sendToServer($msg);
	debug "Sent Action: " .$flag. " on: " .getHex($monID)."\n", "sendPacket", 2;
}

# 0x008c,-1,globalmessage,2:4
sub sendChat {
	my ($self, $message) = @_;
	$message = "|00$message" if ($config{chatLangCode} && $config{chatLangCode} ne "none");

	my ($data, $charName); # Type: Bytes
	$message = stringToBytes($message); # Type: Bytes
	$charName = stringToBytes($char->{name});

	$data = pack('v2 Z*', 0x008C, length($charName) + length($message) + 8, $charName . " : " . $message);

	$self->sendToServer($data);
}

# 0x0090,7,npcclicked,2
sub sendTalk {
	my ($self, $ID) = @_;
	my $msg = pack('v a4 C', 0x0090, $ID, 1);
	$self->sendToServer($msg);
	debug "Sent talk: ".getHex($ID)."\n", "sendPacket", 2;
}

# 0x0094,6,getcharnamerequest,2
sub sendGetPlayerInfo {
	my ($self, $ID) = @_;
	my $msg = pack('v a4', 0x0094, $ID);
	$self->sendToServer($msg);
	debug "Sent get player info: ID - ".getHex($ID)."\n", "sendPacket", 2;
}

# 0x0096,-1,wis,2:4:28
sub sendPrivateMsg {
	my ($self, $user, $message) = @_;
	$message = "|00$message" if ($config{chatLangCode} && $config{chatLangCode} ne "none");
	my $msg = pack('v3 Z24 Z*', 0x0096, length($message) + 29, stringToBytes($user), stringToBytes($message));
	$self->sendToServer($msg);
}

# 0x0099,-1,gmmessage,2:4
sub sendGMMessage {
	my ($self, $color, $message) = @_;
	my $msg = pack('v2 Z*', 0x0099, length($message) + 29, stringToBytes($color.$message));
	$self->sendToServer($msg);
}

# 0x009b,5,changedir,2:4
sub sendLook {
	my ($self, $body, $head) = @_;
	my $msg = pack('v C2', 0x009B, $head, $body);
	$self->sendToServer($msg);
	debug "Sent look: $body $head\n", "sendPacket", 2;
	$char->{look}{head} = $head;
	$char->{look}{body} = $body;
}

# 0x009f,6,takeitem,2
sub sendTake {
	my ($self, $itemID) = @_;
	my $msg = pack('v a4', 0x009F, $itemID);
	$self->sendToServer($msg);
	debug "Sent take\n", "sendPacket", 2;
}

# 0x00a2,6,dropitem,2:4
sub sendDrop {
	my ($self, $index, $amount) = @_;
	my $msg = pack('v3', 0x00A2, $index, $amount);
	$self->sendToServer($msg);
	debug "Sent drop: $index x $amount\n", "sendPacket", 2;
}

# 0x00a7,8,useitem,2:4
sub sendItemUse {
	my ($self, $ID, $targetID) = @_;
	my $msg = pack('v2 a4', 0x00A7, $ID, $targetID);
	$self->sendToServer($msg);
	debug "Item Use: $ID\n", "sendPacket", 2;
}

# 0x00a9,6,equipitem,2:4
sub sendEquip {
	my ($self, $index, $type) = @_;
	my $msg = pack('v3', 0x00A9, $index, $type);
	$self->sendToServer($msg);
	debug "Sent Equip: $index Type: $type\n" , 2;
}

# 0x00ab,4,unequipitem,2
sub sendUnequip {
	my ($self, $index) = @_;
	my $msg = pack('v2', 0x00AB, $index);
	$self->sendToServer($msg);
	debug "Sent Unequip: $index\n", "sendPacket", 2;
}

# 0x00b2,3,restart,2
sub sendRespawn {
	$_[0]->sendToServer(pack('v C', 0x00B2, 0));
	debug "Sent Respawn\n", "sendPacket", 2;
}

# 0x00b8,7,npcselectmenu,2:6
sub sendTalkResponse {
	my ($self, $ID, $response) = @_;
	my $msg = pack('v a4 C', 0x00B8, $ID ,$response);
	$self->sendToServer($msg);
	debug "Sent talk respond: ".getHex($ID).", $response\n", "sendPacket", 2;
}

# 0x00b9,6,npcnextclicked,2
sub sendTalkContinue {
	my ($self, $ID) = @_;
	my $msg = pack('v a4', 0x00B9, $ID);
	$self->sendToServer($msg);
	debug "Sent talk continue: ".getHex($ID)."\n", "sendPacket", 2;
}

# 0x00bb,5,statusup,2:4
sub sendAddStatusPoint {
	my ($self, $statusID) = @_;
	my $msg = pack('v2 C', 0x00BB, $statusID, 1);
	$self->sendToServer($msg);
}

# 0x00bf,3,emotion,2
sub sendEmotion {
	my ($self, $ID) = @_;
	my $msg = pack('v C', 0x00BF, $ID);
	$self->sendToServer($msg);
	debug "Sent Emotion\n", "sendPacket", 2;
}

# 0x00c1,2,howmanyconnections,0
sub sendWho {
	$_[0]->sendToServer(pack('v', 0x00C1));
	debug "Sent Who\n", "sendPacket", 2;
}

# 0x00c5,7,npcbuysellselected,2:6
sub sendNPCBuySellList { # type:0 get store list, type:1 get sell list
	my ($self, $ID, $type) = @_;
	my $msg = pack('v a4 C', 0x00C5, $ID , $type);
	$self->sendToServer($msg);
	debug "Sent get ".($type ? "buy" : "sell")." list to NPC: ".getHex($ID)."\n", "sendPacket", 2;
}

# 0x00c8,-1,npcbuylistsend,2:4
sub sendBuy {
	my ($self, $ID, $amount) = @_;
	my $msg = pack('v3', 0x00C8, $amount, $ID);
	$self->sendToServer($msg);
	debug "Sent buy: ".getHex($ID)."\n", "sendPacket", 2;
}

# 0x00c9,-1,npcselllistsend,2:4
sub sendSellBulk {
	my ($self, $r_array) = @_;
	my $sellMsg;
	for (my $i = 0; $i < @{$r_array}; $i++) {
		$sellMsg .= pack('v*', $r_array->[$i]{index}, $r_array->[$i]{amount});
		debug "Sent bulk sell: $r_array->[$i]{index} x $r_array->[$i]{amount}\n", "d_sendPacket", 2;
	}

	my $msg = pack('v2', 0x00C9, length($sellMsg) + 4) . $sellMsg;
	$self->sendToServer($msg);
}

# 0x00cc,6,gmkick,2
sub sendGMKick {
	my ($self, $ID) = @_;
	my $msg = pack('v V', 0x00CC, $ID);
	$self->sendToServer($msg);
}

# 0x00ce,2,killall,0
sub sendGMKick {
	$_[0]->sendToServer(pack('v', 0x00CE));
}

# 0x00cf,27,wisexin,2:26
sub sendIgnore {
	my ($self, $name, $flag) = @_;
	my $name = stringToBytes($name);
	my $msg = pack('v Z24 C', 0x00CF, $name, $flag);
	$self->sendToServer($msg);
	debug "Sent Ignore: $name, $flag\n", "sendPacket", 2;
}

# 0x00d0,3,wisall,2
sub sendIgnoreAll {
	my ($self, $flag) = @_;
	my $msg = pack('v C', 0x00D0, $flag);
	$self->sendToServer($msg);
	debug "Sent Ignore All: $flag\n", "sendPacket", 2;
}

# 0x00d3,2,wisexlist,0
sub sendIgnoreListGet {
	$_[0]->sendToServer(pack('v', 0x00D3));
	debug "Sent get Ignore List Get.\n", "sendPacket", 2;
}

# 0x00d5,-1,createchatroom,2:4:6:7:15
sub sendChatRoomCreate {
	my ($self, $title, $limit, $public, $password) = @_;
	my $msg = pack('v3 C Z8 Z*', 0x00D5, length($title) + 15, $limit, $public, stringToBytes($password), stringToBytes($title));
	$self->sendToServer($msg);
	debug "Sent Create Chat Room: $title, $limit, $public, $password\n", "sendPacket", 2;
}

# 0x00d9,14,chataddmember,2:6
sub sendChatRoomJoin {
	my ($self, $ID, $password) = @_;
	my $msg = pack('v a4 Z8', 0x00D9, $ID, stringToBytes($password));
	$self->sendToServer($msg);
	debug "Sent Join Chat Room: ".getHex($ID)." $password\n", "sendPacket", 2;
}

# 0x00de,-1,chatroomstatuschange,2:4:6:7:15
sub sendChatRoomChange {
	my ($self, $title, $limit, $public, $password) = @_;
	my $msg = pack('v3 C Z8 Z*', 0x00DE, length($title) + 15, $limit, $public, stringToBytes($password), stringToBytes($title));
	$self->sendToServer($msg);
	debug "Sent Change Chat Room: $title, $limit, $public, $password\n", "sendPacket", 2;
}

# 0x00e0,30,changechatowner,2:6
sub sendChatRoomBestow {
	my ($self, $name) = @_;
	my $msg = pack('v x4 Z24', 0x00E0, stringToBytes($name));
	$self->sendToServer($msg);
	debug "Sent Chat Room Bestow: $name\n", "sendPacket", 2;
}

# 0x00e2,26,kickfromchat,2
sub sendChatRoomKick {
	my ($self, $name) = @_;
	my $msg = pack('v Z24', 0x00E2, stringToBytes($name));
	$self->sendToServer($msg);
	debug "Sent Chat Room Kick: $name\n", "sendPacket", 2;
}

# 0x00e3,2,chatleave,0
sub sendChatRoomLeave {
	$_[0]->sendToServer(pack('v', 0x00E3));
	debug "Sent Leave Chat Room\n", "sendPacket", 2;
}

# 0x00e4,6,traderequest,2
sub sendDeal {
	my ($self, $ID) = @_;
	my $msg = pack('v a4', 0x00E4, $ID);
	$_[0]->sendToServer($msg);
	debug "Sent Initiate Deal: ".getHex($ID)."\n", "sendPacket", 2;
}

# 0x00e6,3,tradeack,2
sub sendDealAccept {
	my $msg = pack('v C', 0x00E6, 3);
	$_[0]->sendToServer($msg);
	debug "Sent Accept Deal\n", "sendPacket", 2;
}

# 0x00e8,8,tradeadditem,2:4
sub sendDealAddItem {
	my ($self, $index, $amount) = @_;
	my $msg = pack('v2 V', 0x00E8, $index, $amount);
	$_[0]->sendToServer($msg);
	debug "Sent Deal Add Item: $index, $amount\n", "sendPacket", 2;
}

# 0x00eb,2,tradeok,0
sub sendDealFinalize {
	$_[0]->sendToServer(pack('v', 0x00EB));
	debug "Sent Deal OK\n", "sendPacket", 2;
}

# 0x00ed,2,tradecancel,0
sub sendCurrentDealCancel {
	$_[0]->sendToServer(pack('v', 0x00ED));
	debug "Sent Cancel Current Deal\n", "sendPacket", 2;
}

# 0x00ef,2,tradecommit,0
sub sendDealTrade {
	$_[0]->sendToServer(pack('v', 0x00EF));
	debug "Sent Deal Trade\n", "sendPacket", 2;
}

# 0x00f3,8,movetokafra,2:4
sub sendStorageAdd {
	my ($self, $index, $amount) = @_;
	my $msg = pack('v2 V', 0x00F3, $index, $amount);
	$self->sendToServer($msg);
	debug "Sent Storage Add: $index x $amount\n", "sendPacket", 2;
}

# 0x00f5,8,movefromkafra,2:4
sub sendStorageGet {
	my ($self, $index, $amount) = @_;
	my $msg = pack('v2 V', 0x00F5, $index, $amount);
	$self->sendToServer($msg);
	debug "Sent Storage Get: $index x $amount\n", "sendPacket", 2;
}

# 0x00f7,2,closekafra,0
sub sendStorageClose {
	$_[0]->sendToServer(pack('v', 0x00F7));
	debug "Sent Storage Done\n", "sendPacket", 2;
}

# 0x00f9,26,createparty,2
sub sendPartyOrganize {
	my ($self, $name) = @_;
	my $msg = pack('v Z24', 0x00F9, stringToBytes($name));
	$self->sendToServer($msg);
	debug "Sent Organize Party: $name\n", "sendPacket", 2;
}

# 0x00fc,6,partyinvite,2
sub sendPartyJoinRequest {
	my ($self, $ID) = @_;
	my $msg = pack('v a4', 0x00FC, $ID);
	$self->sendToServer($msg);
	debug "Sent Request Join Party: ".getHex($ID)."\n", "sendPacket", 2;
}

# 0x00ff,10,replypartyinvite,2:6
sub sendPartyJoin {
	my ($self, $ID, $flag) = @_;
	my $msg = pack('v a4 V', 0x00FF, $ID, $flag);
	$self->sendToServer($msg);
	debug "Sent Join Party: ".getHex($ID).", $flag\n", "sendPacket", 2;
}

# 0x0100,2,leaveparty,0
sub sendPartyLeave {
	$_[0]->sendToServer(pack('v', 0x0100));
	debug "Sent Leave Party\n", "sendPacket", 2;
}

# 0x0102,6,partychangeoption,2:4
sub sendPartyOption {
	my ($self, $exp, $item) = @_;
	my $msg = pack('v3', 0x0102, $exp, $item);
	$self->sendToServer($msg);
	debug "Sent Leave Party\n", "sendPacket", 2;
}

# 0x0103,30,removepartymember,2:6
sub sendPartyKick {
	my ($self, $ID, $name) = @_;
	my $msg = pack('v a4 Z24', 0x0103, $ID, stringToBytes($name));
	$self->sendToServer($msg);
	debug "Sent Kick Party: ".getHex($ID).", $name\n", "sendPacket", 2;
}

# 0x0108,-1,partymessage,2:4
sub sendPartyChat {
	my ($self, $message) = @_;
	$message = "|00$message" if ($config{chatLangCode} && $config{chatLangCode} ne "none");
	my $msg = pack('v2 Z*',0x0108, length($char->{name}) + length($message) + 8, stringToBytes($char->{name}) . " : " . stringToBytes($message));
	$self->sendToServer($msg);
}

# 0x0112,4,skillup,2
sub sendAddSkillPoint {
	my ($self, $skillID) = @_;
	my $msg = pack('v2', 0x0112, $skillID);
	$self->sendToServer($msg);
}

# 0x0113,10,useskilltoid,2:4:6
sub sendSkillUse {
	my ($self, $ID, $lv, $targetID) = @_;
	my $msg;

	my %args;
	$args{ID} = $ID;
	$args{lv} = $lv;
	$args{targetID} = $targetID;
	Plugins::callHook('packet_pre/sendSkillUse', \%args);
	if ($args{return}) {
		$self->sendToServer($args{msg});
		return;
	}

	$msg = pack('v3 a4', 0x0113, $lv, $ID, $targetID);
	$self->sendToServer($msg);
	debug "Skill Use: $ID\n", "sendPacket", 2;
}

# 0x0116,10,useskilltopos,2:4:6:8
sub sendSkillUseLoc {
	my ($self, $ID, $lv, $x, $y) = @_;
	my $msg = pack('v5', 0x0116, $lv, $ID, $x, $y);
	$self->sendToServer($msg);
	debug "Skill Use on Location: $ID, ($x, $y)\n", "sendPacket", 2;
}

# 0x0118,2,stopattack,0
sub sendAttackStop {
	$_[0]->sendToServer(pack('v', 0x0118));
	debug "Sent stop attack.\n", "sendPacket", 2;
}

# 0x011b,20,useskillmap,2:4
sub sendWarpTele { # type: 26=tele, 27=warp
	my ($self, $skillID, $map) = @_;
	my $msg = pack('v2 Z16', 0x011B, $skillID, stringToBytes($map));
	$self->sendToServer($msg);
	debug "Sent ". ($skillID == 26 ? "Teleport" : "Open Warp") . "\n", "sendPacket", 2
}

# 0x011d,2,requestmemo,0
sub sendMemo {
	$_[0]->sendToServer(pack('v', 0x011D));
	debug "Sent Memo\n", "sendPacket", 2;
}

# 0x0126,8,putitemtocart,2:4
sub sendCartAdd {
	my ($self, $index, $amount) = @_;
	my $msg = pack('v2 V', 0x0126, $index, $amount);
	$self->sendToServer($msg);
	debug "Sent Cart Add: $index x $amount\n", "sendPacket", 2;
}

# 0x0127,8,getitemfromcart,2:4
sub sendCartGet {
	my ($self, $index, $amount) = @_;
	my $msg = pack('v2 V', 0x0127, $index, $amount);
	$self->sendToServer($msg);
	debug "Sent Cart Get: $index x $amount\n", "sendPacket", 2;
}

# 0x0128,8,movefromkafratocart,2:4
sub sendStorageGetToCart {
	my ($self, $index, $amount) = @_;
	my $msg = pack('v2 V', 0x0128, $index, $amount);
	$self->sendToServer($msg);
	debug "Sent Storage Get From Cart: $index x $amount\n", "sendPacket", 2;
}

# 0x0129,8,movetokafrafromcart,2:4
sub sendStorageAddFromCart {
	my ($self, $index, $amount) = @_;
	my $msg = pack('v2 V', 0x0129, $index, $amount);
	$self->sendToServer($msg);
	debug "Sent Storage Add From Cart: $index x $amount\n", "sendPacket", 2;
}

# 0x012a,2,removeoption,0
sub sendCompanionRelease {
	$_[0]->sendToServer(pack('v', 0x012A));
	debug "Sent Companion Release (Cart, Falcon or Pecopeco)\n", "sendPacket", 2;
}

# 0x012e,2,closevending,0
sub sendCloseShop {
	$_[0]->sendToServer(pack('v', 0x012E));
	debug "Shop Closed\n", "sendPacket", 2;
}

# 0x0130,6,vendinglistreq,2
sub sendEnteringVender {
	my ($self, $ID) = @_;
	my $msg = pack('v a4', 0x0130, $ID);
	$self->sendToServer($msg);
	debug "Sent Entering Vender: ".getHex($ID)."\n", "sendPacket", 2;
}

# 0x0134,-1,purchasereq,2:4:8
sub sendBuyVender {
	my ($self, $venderID, $ID, $amount) = @_;
	my $len = 12; #temporary, this is a complex packet
	my $msg = pack('v2 a4 v2', 0x0134, $len, $venderID, $amount, $ID);
	$self->sendToServer($msg);
	debug "Sent Vender Buy: ".getHex($ID)."\n", "sendPacket";
}

# 0x013f,26,itemmonster,2
# clif_parse_GM_Monster_Item
sub sendGmMonsterItem {
	my ($self, $name) = @_;
	my $packet = pack('v a24', 0x013F, stringToBytes($name));
	$self->sendToServer($packet);
}

# 0x0140,22,mapmove,2:18:20
# clif_parse_MapMove
sub sendGmMapMove {
	my ($self, $name, $x, $y) = @_;
	my $packet = pack('v Z16 v2', 0x013F, stringToBytes($name), $x, $y);
	$self->sendToServer($packet);
}

# 0x0143,10,npcamountinput,2:6
sub sendTalkNumber {
	my ($self, $ID, $number) = @_;
	my $msg = pack('v a4 V', 0x0143, $ID, $number);
	$self->sendToServer($msg);
	debug "Sent talk number: ".getHex($ID).", $number\n", "sendPacket", 2;
}

# 0x0146,6,npccloseclicked,2
sub sendTalkCancel {
	my ($self, $ID) = @_;
	my $msg = pack('v a4', 0x0146, $ID);
	$self->sendToServer($msg);
	debug "Sent talk cancel: ".getHex($ID)."\n", "sendPacket", 2;
}

# 0x0149,9,gmreqnochat,2:6:7
sub sendAlignment {
	my ($self, $ID, $alignment) = @_;
	my $msg = pack('v a4 v', 0x0149, $ID, $alignment);
	$self->sendToServer($msg);
	debug "Sent Alignment: ".getHex($ID).", $alignment\n", "sendPacket", 2;
}

# 0x014d,2,guildcheckmaster,0
sub sendGuildMasterMemberCheck {
	$_[0]->sendToServer(pack('v', 0x014D));
	debug "Sent Guild Master/Member Check.\n", "sendPacket";
}

# 0x014f,6,guildrequestinfo,2
sub sendGuildRequestInfo {
	my ($self, $page) = @_; # page 0-4
	my $msg = pack('v V', 0x014f, $page);
	$self->sendToServer($msg);
	debug "Sent Guild Request Page : ".$page."\n", "sendPacket";
}

# 0x0151,6,guildrequestemblem,2
sub sendGuildRequestEmblem {
	my ($self, $guildID) = @_;
	my $msg = pack('v V', 0x0151, $guildID);
	$self->sendToServer($msg);
	debug "Sent Guild Request Emblem.\n", "sendPacket";
}

# 0x0153,-1,guildchangeemblem,2:4
sub sendGuildChangeEmblem {
	my ($self, $guildID, $emblem) = @_;
	my $msg = pack('v a4 a*', 0x0153, $guildID, $emblem);
	$self->sendToServer($msg);
	debug "Sent Change Emblem: ".getHex($charID)." $guildID\n", "sendPacket", 2;
}

# 0x0155,-1,guildchangememberposition,2
sub sendGuildMemberTitleSelect { # set the title for a member
	my ($self, $accountID, $charID, $index) = @_;
	my $msg = pack('v a4 a4 V', 0x0155, $accountID, $charID ,$index);
	$self->sendToServer($msg);
	debug "Sent Change Guild title: ".getHex($charID)." $index\n", "sendPacket", 2;
}

# 0x0159,54,guildleave,2:6:10:14
sub sendGuildLeave {
	my ($self, $reason) = @_;
	my $msg = pack('v a4 a4 Z40', 0x0159, $accountID, $charID, stringToBytes($reason));
	$self->sendToServer($msg);
	debug "Sent Guild Leave: $reason (".getHex($msg).")\n", "sendPacket";
}

# 0x015b,54,guildexpulsion,2:6:10:14
sub sendGuildMemberKick {
	my ($self, $guildID, $accountID, $charID, $cause) = @_;
	my $msg = pack('v a4 a4 a4 a40', 0x015B, $guildID, $accountID, $charID, stringToBytes($cause));
	$self->sendToServer($msg);
	debug "Sent Guild Kick: ".getHex($charID)."\n", "sendPacket";
}

# 0x015d,42,guildbreak,2
sub sendGuildBreak {
	my ($self, $guildName) = @_;
	my $msg = pack('v a40', 0x015D, stringToBytes($guildName));
	$self->sendToServer($msg);
	debug "Sent Guild Break: $guildName\n", "sendPacket", 2;
}

# 0x0161,-1,guildchangepositioninfo,2
# TODO: 2x index?
sub sendGuildRankChange { # change the title for a certain index, i would  guess 0 is the top rank, but i dont know
	my ($self, $index, $permissions, $tax, $title) = @_;
	my $msg = pack('v2 V4 a24', 0x0161, 44, $index, $permissions, $index, $tax, stringToBytes($title));
		# packet length, we can actually send multiple titles in the same packet if we wanted to
		# index of this rank in the list
		# this is their abilities, not sure what format
		#pack("V1", $index) . # isnt even used on emulators, but leave in case Aegis wants this
		# guild tax amount, not sure what format
	$self->sendToServer($msg);
	debug "Sent Set Guild title: $index $title\n", "sendPacket", 2;
}

# 0x0165,30,createguild,6
sub sendGuildCreate {
	my ($self, $name) = @_;
	my $msg = pack('v a4 a24', 0x0165, $accountID, stringToBytes($name));
	$self->sendToServer($msg);
	debug "Sent Guild Create: $name\n", "sendPacket", 2;
}

# 0x0168,14,guildinvite,2
sub sendGuildJoinRequest {
	my ($self, $ID) = @_;
	my $msg = pack('v a4 a4 a4', 0x0168, $ID, $accountID, $charID);
	$self->sendToServer($msg);
	debug "Sent Request Join Guild: ".getHex($ID)."\n", "sendPacket";
}

# 0x016b,10,guildreplyinvite,2:6
sub sendGuildJoin {
	my ($self, $ID, $flag) = @_;
	my $msg = pack('v a4 V', 0x016B, $ID, $flag);
	$self->sendToServer($msg);
	debug "Sent Join Guild : ".getHex($ID).", $flag\n", "sendPacket";
}

# 0x016e,186,guildchangenotice,2:6:66
sub sendGuildNotice { # sets the notice/announcement for the guild
	my ($self, $guildID, $name, $notice) = @_;
	my $msg = pack('v a4 a60 a120', 0x016E, $guildID, stringToBytes($name), stringToBytes($notice));
	$self->sendToServer($msg);
	debug "Sent Change Guild Notice: $notice\n", "sendPacket", 2;
}

# 0x0170,14,guildrequestalliance,2
sub sendGuildSetAlly {
	my ($self, $targetAID, $myAID, $charID) = @_;
	my $msg = pack('v a4 a4 a4', 0x0170, $targetAID, $myAID, $charID);
	$self->sendToServer($msg);

}
# 0x0172,10,guildreplyalliance,2:6
sub sendGuildAlly {
	my ($self, $ID, $flag) = @_;
	my $msg = pack('v a4 V', 0x0172, $ID, $flag);
	$self->sendToServer($msg);
	debug "Sent Ally Guild : ".getHex($ID).", $flag\n", "sendPacket", 2;
}

# 0x0178,4,itemidentify,2
sub sendIdentify {
	my ($self, $index) = @_;
	my $msg = pack('v2', 0x0178, $index);
	$self->sendToServer($msg);
	debug "Sent Identify: $index\n", "sendPacket", 2;
}

# 0x017a,4,usecard,2
sub sendCardMergeRequest {
	my ($self, $card_index) = @_;
	my $msg = pack('v2', 0x017A, $card_index);
	$self->sendToServer($msg);
	debug "Sent Card Merge Request: $card_index\n", "sendPacket";
}

# 0x017c,6,insertcard,2:4
sub sendCardMerge {
	my ($self, $card_index, $item_index) = @_;
	my $msg = pack('v3', 0x017C, $card_index, $item_index);
	$self->sendToServer($msg);
	debug "Sent Card Merge: $card_index, $item_index\n", "sendPacket";
}

# 0x017e,-1,guildmessage,2:4
sub sendGuildChat {
	my ($self, $message) = @_;
	$message = "|00$message" if ($config{chatLangCode} && $config{chatLangCode} ne "none");
	my $data = pack('v2 Z*',0x017E, length($char->{name}) + length($message) + 8, stringToBytes($char->{name}) . " : " . stringToBytes($message));
	$self->sendToServer($data);
}

# 0x0180,6,guildopposition,2


# 0x0183,10,guilddelalliance,2:6


# 0x018a,4,quitgame,0
sub sendQuit {
	$_[0]->sendToServer(pack('v x2', 0x018A));
	debug "Sent Quit\n", "sendPacket", 2;
}

# 0x018e,10,producemix,2:4:6:8
sub sendProduceMix {
	my ($self, $ID,
		# nameIDs for added items such as Star Crumb or Flame Heart
		$item1, $item2, $item3) = @_;

	my $msg = pack('v5', 0x018E, $ID, $item1, $item2, $item3);
	$self->sendToServer($msg);
	debug "Sent Forge, Produce Item: $ID\n" , 2;
}

# 0x0190,90,useskilltoposinfo,2:4:6:8:10
sub sendSkillUseLocInfo {
	my ($self, $ID, $lv, $x, $y, $moreinfo) = @_;

	my $msg = pack('v5 Z80', 0x0190, $lv, $ID, $x, $y, $moreinfo);

	$self->sendToServer($msg);
	debug "Skill Use on Location: $ID, ($x, $y)\n", "sendPacket", 2;
}

# 0x0193,6,solvecharname,2
sub sendGetCharacterName {
	my ($self, $ID) = @_;
	my $msg = pack('v a4', 0x0193, $ID);
	$self->sendToServer($msg);
	debug "Sent get character name: ID - ".getHex($ID)."\n", "sendPacket", 2;
}

# 0x0197,4,resetchar,2
sub sendGmResetChar { # type:0 status, type:1 skills
	my ($self, $type) = @_;
	my $msg = pack('v2', 0x0197, $type);
	$self->sendToServer($msg);
	debug "Sent GM Reset State.\n", "sendPacket", 2;
}

# 0x0198,8,changemaptype,2:4:6
sub sendGmChangeMapType { # type is of .gat format
	my ($self, $x, $y, $type) = @_;
	my $msg = pack('v4', 0x0198, $x, $y, $type);
	$self->sendToServer($msg);
	debug "Sent GM Change Map Type.\n", "sendPacket", 2;
}

# 0x019c,-1,lgmmessage,2:4


# 0x019d,6,gmhide,0
# TODO: test this
sub sendGmHide {
	my ($self) = @_;
	my $msg = pack('v x4', 0x019D);
	$self->sendToServer($msg);
	debug "Sent GM Hide.\n", "sendPacket", 2;
}

# 0x019f,6,catchpet,2
sub sendPetCapture {
	my ($self, $monID) = @_;
	my $msg = pack('v a4', 0x019F, $monID);
	$self->sendToServer($msg);
	debug "Sent pet capture: ".getHex($monID)."\n", "sendPacket", 2;
}

# 0x01a1,3,petmenu,2
sub sendPetMenu {
	my ($self, $type) = @_; # 1:feed, 0:info, 2:performance, 3:to egg, 4:uneq item
	my $msg = pack('v C', 0x01A1, $type);
	$self->sendToServer($msg);
	debug "Sent Pet Menu\n", "sendPacket", 2;
}

# 0x01a5,26,changepetname,2
sub sendPetName {
	my ($self, $name) = @_;
	my $msg = pack('v a24', 0x01A5, stringToBytes($name));
	$self->sendToServer($msg);
	debug "Sent Pet Rename: $name\n", "sendPacket", 2;
}

# 0x01a7,4,selectegg,2
sub sendPetHatch {
	my ($self, $index) = @_;
	my $msg = pack('v2', 0x01A7, $index);
	$self->sendToServer($msg);
	debug "Sent Incubator hatch: $index\n", "sendPacket", 2;
}

# 0x01a9,6,sendemotion,2
sub sendPetEmotion{
	my ($self, $emoticon) = @_;
	my $msg = pack('v V', 0x01A9, $emoticon);
	$self->sendToServer($msg);
	debug "Sent Pet Emotion.\n", "sendPacket", 2;
}

# 0x01ae,4,selectarrow,2
sub sendArrowCraft {
	my ($self, $index) = @_;
	my $msg = pack('v2', 0x01AE, $index);
	$self->sendToServer($msg);
	debug "Sent Arrowmake: $index\n", "sendPacket", 2;
}

# 0x01af,4,changecart,2
sub sendChangeCart { # lvl: 1, 2, 3, 4, 5
	my ($self, $lvl) = @_;
	my $msg = pack('v2', 0x01AF, $lvl);
	$self->sendToServer($msg);
	debug "Sent Cart Change to : $lvl\n", "sendPacket", 2;
}

# NOTE: complex packet structure
# 0x01b2,-1,openvending,2:4:84:85
sub sendOpenShop {
	my ($self, $title, $items) = @_;
	my $length = 0x55 + 0x08 * @{$items};
	my $msg = pack('v2 a80 C', 0x01B2, $length, stringToBytes($title), 1);
	foreach my $item (@{$items}) {
		$msg .= pack('v2 V', $item->{index}, $item->{amount}, $item->{price});
	}
	$self->sendToServer($msg);
}

# 0x01ba,26,remove,2
sub sendGmRemove {
	my ($self, $playerName) = @_;
	my $packet = pack('v a24', 0x01BA, stringToBytes($playerName));
	$self->sendToServer($packet);
}

# 0x01bb,26,shift,2
sub sendGmShift {
	my ($self, $playerName) = @_;
	my $packet = pack('v a24', 0x01BB, stringToBytes($playerName));
	$self->sendToServer($packet);
}

# 0x01bc,26,recall,2
sub sendGmRecall {
	my ($self, $playerName) = @_;
	my $packet = pack('v a24', 0x01BC, stringToBytes($playerName));
	$self->sendToServer($packet);
}

# 0x01bd,26,summon,2
sub sendGmSummon {
	my ($self, $playerName) = @_;
	my $packet = pack('v a24', 0x01BD, stringToBytes($playerName));
	$self->sendToServer($packet);
}

# 0x01ce,6,autospell,2
sub sendAutoSpell {
	my ($self, $ID) = @_;
	my $msg = pack('v C x3', 0x01CE, $ID);
	$self->sendToServer($msg);
}

# 0x01d5,-1,npcstringinput,2:4:8
sub sendTalkText {
	my ($self, $ID, $input) = @_;
	my $msg = pack('v2 a4 Z*', 0x01D5, length($input)+length($ID)+5, $ID, stringToBytes($input));
	$self->sendToServer($msg);
	debug "Sent talk text: ".getHex($ID).", $input\n", "sendPacket", 2;
}

# 0x01df,6,gmreqaccname,2


# 0x01e7,2,sndoridori,0
sub sendSuperNoviceDoriDori {
	$_[0]->sendToServer(pack('v', 0x01E7));
	debug "Sent Super Novice dori dori\n", "sendPacket", 2;
}

# 0x01e8,28,createparty2,2
sub sendPartyOrganize {
	my ($self, $name, $share1, $share2) = @_;
	# FIXME: what are shared with $share1 and $share2? experience? item? vice-versa?
	my $msg = pack('v Z24 C2', 0x01E8, stringToBytes($name), $share1, $share2);
	$self->sendToServer($msg);
	debug "Sent Organize Party: $name\n", "sendPacket", 2;
}

# 0x01ed,2,snexplosionspirits,0
sub sendSuperNoviceExplosion {
	$_[0]->sendToServer(pack('v', 0x01ED));
	debug "Sent Super Novice Explosion\n", "sendPacket", 2;
}

# 0x01f7,14,adoptreply,0
sub SendAdoptReply {
	my ($self, $parentID1, $parentID2, $result) = @_;
	my $msg = pack('v V3', 0x01F7, $parentID1, $parentID2, $result);
	$self->sendToServer($msg);
	debug "Sent Adoption Reply.\n", "sendPacket", 2;
}

# 0x01f9,6,adoptrequest,0
sub SendAdoptRequest {
	my ($self, $ID) = @_;
	my $msg = pack('v V', 0x01F9, $ID);
	$self->sendToServer($msg);
	debug "Sent Adoption Request.\n", "sendPacket", 2;
}

# 0x01fd,4,repairitem,2
sub sendRepairItem {
	my ($self, $args) = @_;
	my $msg = pack('C2 v2 V2 C', 0x01FD, $args->{index}, $args->{nameID}, $args->{status}, $args->{status2}, $args->{listID});
	$self->sendToServer($msg);
	debug ("Sent repair item: ".$args->{index}."\n", "sendPacket", 2);
}

# 0x0202,26,friendslistadd,2
sub sendFriendRequest {
	my ($self, $name) = @_;
	my $msg = pack('v Z24', 0x0202, stringToBytes($name));
	$self->sendToServer($msg);
	debug "Sent Request to be a friend: $name\n", "sendPacket";
}

# 0x0203,10,friendslistremove,2:6
sub sendFriendRemove {
	my ($self, $accountID, $charID) = @_;
	my $msg = pack('v a4 a4', 0x0203, $accountID, $charID);
	$self->sendToServer($msg);
	debug "Sent Remove a friend\n", "sendPacket";
}

# 0x0208,11,friendslistreply,2:6:10
# sendFriendReject:0/sendFriendAccept:1
sub sendFriendListReply {
	my ($self, $accountID, $charID, $flag) = @_;
	my $msg = pack('v a4 a4 C', 0x0208, $accountID, $charID, $flag);
	$self->sendToServer($msg);
	debug "Sent Reject friend request\n", "sendPacket";
}

1;

=pod
packet_ver: 5
0x0064,55
0x0065,17
0x0066,6
0x0067,37
0x0068,46
0x0069,-1
0x006a,23
0x006b,-1
0x006c,3
0x006d,108
0x006e,3
0x006f,2
0x0070,6
0x0071,28
0x0072,19,wanttoconnection,2:6:10:14:18
0x0073,11
0x0074,3
0x0075,-1
0x0076,9
0x0077,5
0x0078,54
0x0079,53
0x007a,58
0x007b,60
0x007c,41
0x007d,2,loadendack,0
0x007e,6,ticksend,2
0x007f,6
0x0080,7
0x0081,3
0x0082,2
0x0083,2
0x0084,2
0x0085,5,walktoxy,2
0x0086,16
0x0087,12
0x0088,10
0x0089,7,actionrequest,2:6
0x008a,29
0x008b,2
0x008c,-1,globalmessage,2:4
0x008d,-1
0x008e,-1
//0x008f,0
0x0090,7,npcclicked,2
0x0091,22
0x0092,28
0x0093,2
0x0094,6,getcharnamerequest,2
0x0095,30
0x0096,-1,wis,2:4:28
0x0097,-1
0x0098,3
0x0099,-1,gmmessage,2:4
0x009a,-1
0x009b,5,changedir,2:4
0x009c,9
0x009d,17
0x009e,17
0x009f,6,takeitem,2
0x00a0,23
0x00a1,6
0x00a2,6,dropitem,2:4
0x00a3,-1
0x00a4,-1
0x00a5,-1
0x00a6,-1
0x00a7,8,useitem,2:4
0x00a8,7
0x00a9,6,equipitem,2:4
0x00aa,7
0x00ab,4,unequipitem,2
0x00ac,7
//0x00ad,0
0x00ae,-1
0x00af,6
0x00b0,8
0x00b1,8
0x00b2,3,restart,2
0x00b3,3
0x00b4,-1
0x00b5,6
0x00b6,6
0x00b7,-1
0x00b8,7,npcselectmenu,2:6
0x00b9,6,npcnextclicked,2
0x00ba,2
0x00bb,5,statusup,2:4
0x00bc,6
0x00bd,44
0x00be,5
0x00bf,3,emotion,2
0x00c0,7
0x00c1,2,howmanyconnections,0
0x00c2,6
0x00c3,8
0x00c4,6
0x00c5,7,npcbuysellselected,2:6
0x00c6,-1
0x00c7,-1
0x00c8,-1,npcbuylistsend,2:4
0x00c9,-1,npcselllistsend,2:4
0x00ca,3
0x00cb,3
0x00cc,6,gmkick,2
0x00cd,3
0x00ce,2,killall,0
0x00cf,27,wisexin,2:26
0x00d0,3,wisall,2
0x00d1,4
0x00d2,4
0x00d3,2,wisexlist,0
0x00d4,-1
0x00d5,-1,createchatroom,2:4:6:7:15
0x00d6,3
0x00d7,-1
0x00d8,6
0x00d9,14,chataddmember,2:6
0x00da,3
0x00db,-1
0x00dc,28
0x00dd,29
0x00de,-1,chatroomstatuschange,2:4:6:7:15
0x00df,-1
0x00e0,30,changechatowner,2:6
0x00e1,30
0x00e2,26,kickfromchat,2
0x00e3,2,chatleave,0
0x00e4,6,traderequest,2
0x00e5,26
0x00e6,3,tradeack,2
0x00e7,3
0x00e8,8,tradeadditem,2:4
0x00e9,19
0x00ea,5
0x00eb,2,tradeok,0
0x00ec,3
0x00ed,2,tradecancel,0
0x00ee,2
0x00ef,2,tradecommit,0
0x00f0,3
0x00f1,2
0x00f2,6
0x00f3,8,movetokafra,2:4
0x00f4,21
0x00f5,8,movefromkafra,2:4
0x00f6,8
0x00f7,2,closekafra,0
0x00f8,2
0x00f9,26,createparty,2
0x00fa,3
0x00fb,-1
0x00fc,6,partyinvite,2
0x00fd,27
0x00fe,30
0x00ff,10,replypartyinvite,2:6
0x0100,2,leaveparty,0
0x0101,6
0x0102,6,partychangeoption,2:4
0x0103,30,removepartymember,2:6
0x0104,79
0x0105,31
0x0106,10
0x0107,10
0x0108,-1,partymessage,2:4
0x0109,-1
0x010a,4
0x010b,6
0x010c,6
0x010d,2
0x010e,11
0x010f,-1
0x0110,10
0x0111,39
0x0112,4,skillup,2
0x0113,10,useskilltoid,2:4:6
0x0114,31
0x0115,35
0x0116,10,useskilltopos,2:4:6:8
0x0117,18
0x0118,2,stopattack,0
0x0119,13
0x011a,15
0x011b,20,useskillmap,2:4
0x011c,68
0x011d,2,requestmemo,0
0x011e,3
0x011f,16
0x0120,6
0x0121,14
0x0122,-1
0x0123,-1
0x0124,21
0x0125,8
0x0126,8,putitemtocart,2:4
0x0127,8,getitemfromcart,2:4
0x0128,8,movefromkafratocart,2:4
0x0129,8,movetokafrafromcart,2:4
0x012a,2,removeoption,0
0x012b,2
0x012c,3
0x012d,4
0x012e,2,closevending,0
0x012f,-1
0x0130,6,vendinglistreq,2
0x0131,86
0x0132,6
0x0133,-1
0x0134,-1,purchasereq,2:4:8
0x0135,7
0x0136,-1
0x0137,6
0x0138,3
0x0139,16
0x013a,4
0x013b,4
0x013c,4
0x013d,6
0x013e,24
0x013f,26,itemmonster,2
0x0140,22,mapmove,2:18:20
0x0141,14
0x0142,6
0x0143,10,npcamountinput,2:6
0x0144,23
0x0145,19
0x0146,6,npccloseclicked,2
0x0147,39
0x0148,8
0x0149,9,gmreqnochat,2:6:7
0x014a,6
0x014b,27
0x014c,-1
0x014d,2,guildcheckmaster,0
0x014e,6
0x014f,6,guildrequestinfo,2
0x0150,110
0x0151,6,guildrequestemblem,2
0x0152,-1
0x0153,-1,guildchangeemblem,2:4
0x0154,-1
0x0155,-1,guildchangememberposition,2
0x0156,-1
0x0157,6
0x0158,-1
0x0159,54,guildleave,2:6:10:14
0x015a,66
0x015b,54,guildexpulsion,2:6:10:14
0x015c,90
0x015d,42,guildbreak,2
0x015e,6
0x015f,42
0x0160,-1
0x0161,-1,guildchangepositioninfo,2
0x0162,-1
0x0163,-1
0x0164,-1
0x0165,30,createguild,6
0x0166,-1
0x0167,3
0x0168,14,guildinvite,2
0x0169,3
0x016a,30
0x016b,10,guildreplyinvite,2:6
0x016c,43
0x016d,14
0x016e,186,guildchangenotice,2:6:66
0x016f,182
0x0170,14,guildrequestalliance,2
0x0171,30
0x0172,10,guildreplyalliance,2:6
0x0173,3
0x0174,-1
0x0175,6
0x0176,106
0x0177,-1
0x0178,4,itemidentify,2
0x0179,5
0x017a,4,usecard,2
0x017b,-1
0x017c,6,insertcard,2:4
0x017d,7
0x017e,-1,guildmessage,2:4
0x017f,-1
0x0180,6,guildopposition,2
0x0181,3
0x0182,106
0x0183,10,guilddelalliance,2:6
0x0184,10
0x0185,34
//0x0186,0
0x0187,6
0x0188,8
0x0189,4
0x018a,4,quitgame,0
0x018b,4
0x018c,29
0x018d,-1
0x018e,10,producemix,2:4:6:8
0x018f,6
0x0190,90,useskilltoposinfo,2:4:6:8:10
0x0191,86
0x0192,24
0x0193,6,solvecharname,2
0x0194,30
0x0195,102
0x0196,9
0x0197,4,resetchar,2
0x0198,8,changemaptype,2:4:6
0x0199,4
0x019a,14
0x019b,10
0x019c,-1,lgmmessage,2:4
0x019d,6,gmhide,0
0x019e,2
0x019f,6,catchpet,2
0x01a0,3
0x01a1,3,petmenu,2
0x01a2,35
0x01a3,5
0x01a4,11
0x01a5,26,changepetname,2
0x01a6,-1
0x01a7,4,selectegg,2
0x01a8,4
0x01a9,6,sendemotion,2
0x01aa,10
0x01ab,12
0x01ac,6
0x01ad,-1
0x01ae,4,selectarrow,2
0x01af,4,changecart,2
0x01b0,11
0x01b1,7
0x01b2,-1,openvending,2:4:84:85
0x01b3,67
0x01b4,12
0x01b5,18
0x01b6,114
0x01b7,6
0x01b8,3
0x01b9,6
0x01ba,26,remove,2
0x01bb,26,shift,2
0x01bc,26,recall,2
0x01bd,26,summon,2
0x01be,2
0x01bf,3
0x01c0,2
0x01c1,14
0x01c2,10
0x01c3,-1
0x01c4,22
0x01c5,22
0x01c6,4
0x01c7,2
0x01c8,13
0x01c9,97
//0x01ca,0
0x01cb,9
0x01cc,9
0x01cd,30
0x01ce,6,autospell,2
0x01cf,28
0x01d0,8
0x01d1,14
0x01d2,10
0x01d3,35
0x01d4,6
0x01d5,-1,npcstringinput,2:4:8
0x01d6,4
0x01d7,11
0x01d8,54
0x01d9,53
0x01da,60
0x01db,2
0x01dc,-1
0x01dd,47
0x01de,33
0x01df,6,gmreqaccname,2
0x01e0,30
0x01e1,8
0x01e2,34
0x01e3,14
0x01e4,2
0x01e5,6
0x01e6,26
0x01e7,2,sndoridori,0
0x01e8,28,createparty2,2
0x01e9,81
0x01ea,6
0x01eb,10
0x01ec,26
0x01ed,2,snexplosionspirits,0
0x01ee,-1
0x01ef,-1
0x01f0,-1
0x01f1,-1
0x01f2,20
0x01f3,10
0x01f4,32
0x01f5,9
0x01f6,34
0x01f7,14,adoptreply,0
0x01f8,2
0x01f9,6,adoptrequest,0
0x01fa,48
0x01fb,56
0x01fc,-1
0x01fd,4,repairitem,2
0x01fe,5
0x01ff,10
0x0200,26
0x0201,-1
0x0202,26,friendslistadd,2
0x0203,10,friendslistremove,2:6
0x0204,18
0x0205,26
0x0206,11
0x0207,34
0x0208,11,friendslistreply,2:6:10
0x0209,36
0x020a,10
//0x020b,0
//0x020c,0
0x020d,-1
=cut