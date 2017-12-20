pragma solidity ^0.4.17;

/*
    Copyright 2017, RJ Ewing <perissology@protonmail.com>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import "giveth-liquidpledging/contracts/LiquidPledging.sol";
import "giveth-common-contracts/contracts/Escapable.sol";
import "minimetoken/contracts/MiniMeToken.sol";


contract LPPCampaigns is Escapable, TokenController {
    uint constant FROM_OWNER = 0;
    uint constant FROM_PROPOSEDPROJECT = 255;
    uint constant TO_OWNER = 256;
    uint constant TO_PROPOSEDPROJECT = 511;

    LiquidPledging public liquidPledging;

    struct Campaign {
        MiniMeToken token;
        address owner;
        address reviewer;
    }

    mapping (uint64 => Campaign) campaigns;

    event GenerateTokens(uint64 indexed idProject, address addr, uint amount);
    event DestroyTokens(uint64 indexed idProject, address addr, uint amount);

    //== constructor

    function LPPCampaigns(
        LiquidPledging _liquidPledging,
        address _escapeHatchCaller,
        address _escapeHatchDestination
    ) Escapable(_escapeHatchCaller, _escapeHatchDestination) public
    {
        liquidPledging = _liquidPledging;
    }

    //== external

    /// @dev this is called by liquidPledging before every transfer to and from
    ///      a pledgeAdmin that has this contract as its plugin
    /// @dev see ILiquidPledgingPlugin interface for details about context param
    function beforeTransfer(
        uint64 pledgeManager,
        uint64 pledgeFrom,
        uint64 pledgeTo,
        uint64 context,
        uint amount
    ) external returns (uint maxAllowed)
    {
        require(msg.sender == address(liquidPledging));
        var (, , , fromProposedProject, , , ) = liquidPledging.getPledge(pledgeFrom);
        var (, toOwner, , toProposedProject, , , toPledgeState ) = liquidPledging.getPledge(pledgeTo);

        // campaigns can not withdraw funds
        if ( (context == TO_OWNER) && (toPledgeState != LiquidPledgingBase.PledgeState.Pledged) ) {
            return 0;
        }

        // If this campaign is the proposed recipient of delegated funds or funds are being directly
        // transferred to me, ensure that the campaign has not been canceled
        if (context == TO_PROPOSEDPROJECT && isCanceled(toProposedProject)) {
            return 0;
        } else if (context == TO_OWNER && fromProposedProject != idProject && isCanceled(toOwner)) {
            return 0;
        }

        return amount;
    }

    /// @dev this is called by liquidPledging after every transfer to and from
    ///      a pledgeAdmin that has this contract as its plugin
    /// @dev see ILiquidPledgingPlugin interface for details about context param
    function afterTransfer(
        uint64 pledgeManager,
        uint64 pledgeFrom,
        uint64 pledgeTo,
        uint64 context,
        uint amount
    ) external
    {
        require(msg.sender == address(liquidPledging));
        var (, toOwner, , , , , toPledgeState) = liquidPledging.getPledge(pledgeTo);
        var (, fromOwner, , , , , ) = liquidPledging.getPledge(pledgeFrom);

        // only issue tokens when pledge is committed to this campaign
        if (context == TO_OWNER &&
            toPledgeState == LiquidPledgingBase.PledgeState.Pledged) {
            Campaign storage c = campaigns[toOwner];
            require(address(c.token) != 0x0);

            var (, fromAddr , , , , , , ) = liquidPledging.getPledgeAdmin(fromOwner);
            c.token.generateTokens(fromAddr, amount);
            GenerateTokens(toOwner, fromAddr, amount);
        }
    }

    //== public

    function addCampaign(
        string name,
        string url,
        uint64 parentProject,
        address reviewer,
        string tokenName,
        string tokenSymbol
    ) public
    {
        uint64 idProject = liquidPledging.addProject(
            name,
            url,
            address(this),
            parentProject,
            0,
            ILiquidPledgingPlugin(this)
        );

        MiniMeTokenFactory tokenFactory = new MiniMeTokenFactory();
        MiniMeToken token = new MiniMeToken(tokenFactory, 0x0, 0, tokenName, 18, tokenSymbol, false);

        campaigns[idProject] = Campaign(token, msg.sender, reviewer);
    }

    function addCampaign(
      string name,
      string url,
      uint64 parentProject,
      address reviewer,
      string tokenName,
      string tokenSymbol
    ) public
    {
        uint64 idProject = liquidPledging.addProject(
          name,
          url,
          address(this),
          parentProject,
          0,
          ILiquidPledgingPlugin(this)
        );

        campaigns[idProject] = Campaign(token, msg.sender, reviewer);
    }

    function cancelCampaign(uint64 idProject) public {
        Campaign storage c = campaigns[idProject];
        require(msg.sender == c.owner || msg.sender == c.reviewer);
        require(!isCanceled(idProject));

        liquidPledging.cancelProject(idProject);
    }

    function transfer(
        uint64 idProject,
        uint64 idPledge,
        uint amount,
        uint64 idReceiver
    ) public
    {
        Campaign storage d = campaigns[idProject];
        require(msg.sender == d.owner);

        liquidPledging.transfer(
            idProject,
            idPledge,
            amount,
            idReceiver
        );
    }

    function getCampaign(uint64 idProject) public view returns (
        MiniMeToken token,
        address owner
    )
    {
        Campaign storage d = campaigns[idProject];
        token = d.token;
        owner = d.owner;
    }

    function isCanceled(uint64 idProject) public constant returns (bool) {
        return liquidPledging.isProjectCanceled(idProject);
    }

  //TODO this is an issue, need to figure out
    // allows the owner to send any tx, similar to a multi-sig
    // this is necessary b/c the campaign may receive dac/campaign tokens
    // if they transfer a pledge they own to another dac/campaign.
    // this allows the owner to participate in governance with the tokens
    // it holds.
//    function sendTransaction(address destination, uint value, bytes data) public initialized onlyOwner {
//        require(destination.call.value(value)(data));
//    }

    ////////////////
    // TokenController
    ////////////////

    /// @notice Called when `_owner` sends ether to the MiniMe Token contract
    /// @param _owner The address that sent the ether to create tokens
    /// @return True if the ether is accepted, false if it throws
    function proxyPayment(address _owner) public payable returns(bool) {
        return false;
    }

    /// @notice Notifies the controller about a token transfer allowing the
    ///  controller to react if desired
    /// @param _from The origin of the transfer
    /// @param _to The destination of the transfer
    /// @param _amount The amount of the transfer
    /// @return False if the controller does not authorize the transfer
    function onTransfer(address _from, address _to, uint _amount) public returns(bool) {
        return false;
    }

    /// @notice Notifies the controller about an approval allowing the
    ///  controller to react if desired
    /// @param _owner The address that calls `approve()`
    /// @param _spender The spender in the `approve()` call
    /// @param _amount The amount in the `approve()` call
    /// @return False if the controller does not authorize the approval
  function onApprove(address _owner, address _spender, uint _amount) public returns(bool) {
      return false;
  }
}
