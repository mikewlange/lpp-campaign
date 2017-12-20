const LPPCampaignsABI = require('../build/LPPCampaigns.sol').LPPCampaignsAbi;
const LPPCampaignsByteCode = require('../build/LPPCampaigns.sol').LPPCampaignsByteCode;
const generateClass = require('eth-contract-class').default;

const LPPCampaigns = generateClass(LPPCampaignsABI, LPPCampaignsByteCode);

module.exports = LPPCampaigns;
