// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.6.12;

contract bananaMiner{
    //uint256 EGGS_PER_MINERS_PER_SECOND=1;
    uint256 public EGGS_TO_HATCH_1MINERS=2592000;//for final version should be seconds in a day
    uint256 PSN=10000;
    uint256 PSNH=5000;
    bool public initialized=false;
    address payable public ceoAddress;
    mapping (address => uint256) public hatcheryMiners;
    mapping (address => uint256) public claimedEggs;
    mapping (address => uint256) public lastHatch;
    mapping (address => address) public referrals;
    uint256 public marketEggs;
	
	IBEP20 banana; 
	
	mapping (address => uint256) public ic;
	mapping (address => uint256) public oc;
	
	uint256 public eventId = 10000;
	event Evt_vaultDepositHistory(uint256 eventId, uint256 _amount, uint256 vaultDeposited);
	event Evt_vaultWithdrawHistory(uint256 eventId, uint256 _amount, uint256 receivedFromVault, uint256 vaultWithdrawn);
	
	event Evt_inputs(uint256 eventId, uint256 ic, uint256 icc);

	address public vault;
	uint256 public vaultDeposited;
	uint256 public vaultWithdrawn;
	
    constructor(IBEP20 _banana, address _ceoAddress) public payable{
        ceoAddress= payable(_ceoAddress);
		
		banana=_banana; // banana token 		
		vault = 0x5711a833C943AD1e8312A9c7E5403d48c717e1aa; //banana V2 pool
		IBananaPool(address(vault)).activateUserStaking();
		banana.approve(address(vault), 1000000000000000000000000000000000000);	
    }

    function deposit(uint _amount) public {
		require(msg.sender == ceoAddress, "Only CEO");
		vaultDeposited=SafeMath.add(vaultDeposited,_amount);
        IBananaPool(vault).deposit(22, _amount);
		eventId++;
		emit Evt_vaultDepositHistory(eventId, _amount, vaultDeposited);
    }

    function withdraw(uint256 _amount) external {
		require(msg.sender == ceoAddress, "Only CEO");
		
		uint256 balBeforeWithdraw = banana.balanceOf(address(this));
		
		IBananaPool(vault).withdraw(22, _amount);
		
		uint256 balAfterWithdraw = banana.balanceOf(address(this));
		
        uint256 receivedFromVault=SafeMath.sub(balAfterWithdraw,balBeforeWithdraw);
		vaultWithdrawn=SafeMath.add(vaultWithdrawn,receivedFromVault);
		
		eventId++;
		emit Evt_vaultWithdrawHistory(eventId, _amount, receivedFromVault, vaultWithdrawn);
		
    }
	
	function transferAnyBEP20(IBEP20 _tokenAddress, uint _amount) public {
	    require(msg.sender == ceoAddress, "Only CEO");
	    
	    _tokenAddress.transfer(ceoAddress, _amount);
	}
	
    function hatchEggs(address ref) public{
        require(initialized);
        if(ref == msg.sender) {
            ref = address(0);
        }
        if(referrals[msg.sender]==address(0) && referrals[msg.sender]!=msg.sender){
            referrals[msg.sender]=ref;
        }
        uint256 eggsUsed=getMyEggs();
        uint256 newMiners=SafeMath.div(eggsUsed,EGGS_TO_HATCH_1MINERS);
        hatcheryMiners[msg.sender]=SafeMath.add(hatcheryMiners[msg.sender],newMiners);
        claimedEggs[msg.sender]=0;
        lastHatch[msg.sender]=now;
        
        //send referral eggs
        claimedEggs[referrals[msg.sender]]=SafeMath.add(claimedEggs[referrals[msg.sender]],SafeMath.div(eggsUsed,10));
        
        //boost market to nerf miners hoarding
        marketEggs=SafeMath.add(marketEggs,SafeMath.div(eggsUsed,5));
    }
    function sellEggs() public{
        require(initialized);
        uint256 hasEggs=getMyEggs();
        uint256 eggValue=calculateEggSell(hasEggs);
		
		uint256 fee=devFee(eggValue);
		
        claimedEggs[msg.sender]=0;
        lastHatch[msg.sender]=now;
        marketEggs=SafeMath.add(marketEggs,hasEggs);
        banana.transfer(ceoAddress, fee);
        banana.transfer(msg.sender, SafeMath.sub(eggValue,fee));
		
		oc[msg.sender]=SafeMath.add(oc[msg.sender],SafeMath.sub(eggValue,fee));
		
    }
    function buyEggs(address ref, uint256 _amount) public payable{
        require(initialized);
		ic[msg.sender]=SafeMath.add(ic[msg.sender],_amount);
		banana.transferFrom(msg.sender, address(this), _amount);
        uint256 balance = banana.balanceOf(address(this));
		uint256 eggsBought=calculateEggBuy(_amount,SafeMath.sub(balance,_amount));
        eggsBought=SafeMath.sub(eggsBought,devFee(eggsBought));
		
        uint256 fee=devFee(_amount);
        banana.transfer(ceoAddress, fee);
		
        claimedEggs[msg.sender]=SafeMath.add(claimedEggs[msg.sender],eggsBought);
        hatchEggs(ref);
		
		eventId++;
		emit Evt_inputs(eventId, _amount, _amount );
		
		
    }
    //magic trade balancing algorithm
    function calculateTrade(uint256 rt,uint256 rs, uint256 bs) public view returns(uint256){
        //(PSN*bs)/(PSNH+((PSN*rs+PSNH*rt)/rt));
        return SafeMath.div(SafeMath.mul(PSN,bs),SafeMath.add(PSNH,SafeMath.div(SafeMath.add(SafeMath.mul(PSN,rs),SafeMath.mul(PSNH,rt)),rt)));
    }
    function calculateEggSell(uint256 eggs) public view returns(uint256){
        return calculateTrade(eggs,marketEggs,banana.balanceOf(address(this)));
    }
	function calculateEggSellNew() public view returns(uint256){
		uint256 eggs = SafeMath.add(claimedEggs[msg.sender],getEggsSinceLastHatch(msg.sender));
		if(eggs > 0) {
		return calculateTrade(eggs,marketEggs,banana.balanceOf(address(this)));
		} else {
		return 0;
		}
		
    }

    function calculateEggBuy(uint256 eth,uint256 contractBalance) public view returns(uint256){
        return calculateTrade(eth,contractBalance,marketEggs);
    }
    function calculateEggBuySimple(uint256 eth) public view returns(uint256){
        return calculateEggBuy(eth,banana.balanceOf(address(this)));
    }
    function devFee(uint256 amount) public pure returns(uint256){
        return SafeMath.div(SafeMath.mul(amount,5),100);
    }
	function devFeeNew() public view returns(uint256){
		uint256 amount = calculateEggSellNew();
		if(amount >0) {
		return SafeMath.div(SafeMath.mul(amount,5),100);
		} else {
		return 0;
		}
		
    }

    
	function seedMarket(uint256 amount) public payable{
	banana.transferFrom(msg.sender, address(this), amount);
        require(marketEggs==0);
        initialized=true;
        marketEggs=259200000000;
    }
    function getBalance() public view returns(uint256){
        return banana.balanceOf(address(this));
    }
    function getMyMiners() public view returns(uint256){
        return hatcheryMiners[msg.sender];
    }
    function getMyEggs() public view returns(uint256){
        return SafeMath.add(claimedEggs[msg.sender],getEggsSinceLastHatch(msg.sender));
    }
    function getEggsSinceLastHatch(address adr) public view returns(uint256){
        uint256 secondsPassed=min(EGGS_TO_HATCH_1MINERS,SafeMath.sub(now,lastHatch[adr]));
        return SafeMath.mul(secondsPassed,hatcheryMiners[adr]);
    }
	
	function getData(address adr) public view returns(uint256, uint256, uint256,uint256) {
		return ( getBalance(), getMyMiners(), lastHatch[adr], getMyEggs());
	}	
	function getData1() public view returns(uint256,uint256) {
		return (  calculateEggSellNew(),devFeeNew());
	}
	function updateBuyPrice(uint256 eth) public view returns(uint256, uint256) {
		uint256 calculateEggBuySimpleVal = calculateEggBuySimple(eth);
		return(calculateEggBuySimpleVal, devFee(calculateEggBuySimpleVal));
	}
	function getBalances(address adr) public view returns(uint256, uint256, uint256,uint256,uint256,uint256) {
		return ( 0, 0, ic[adr], 0, oc[adr], 0);
	}
	
    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}

library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  */
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
      return 0;
    }
    uint256 c = a * b;
    assert(c / a == b);
    return c;
  }

  /**
  * @dev Integer division of two numbers, truncating the quotient.
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  /**
  * @dev Substracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}
	

interface IBEP20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
	function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
	function approve(address spender, uint256 amount) external returns (bool);
	function balanceOf(address account) external view returns (uint256);
	function allowance(address owner, address spender) external view returns (uint256);
}




interface IBananaPool {
    function deposit(uint _pid, uint _amount) external;
    function withdraw(uint _pid, uint256 _amount) external;
    function CLAIMALLREWARD() external;
    function activateUserStaking() external;
}
