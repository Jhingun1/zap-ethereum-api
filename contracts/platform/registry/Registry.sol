pragma solidity ^0.4.24;
// v1.0

import "../../lib/lifecycle/Destructible.sol";
import "../../lib/ownership/Upgradable.sol";
import "../database/DatabaseInterface.sol";
import "./RegistryInterface.sol";

contract Registry is Destructible, RegistryInterface, Upgradable {

    event NewProvider(
        address indexed provider,
        bytes32 indexed title
    );

    event NewCurve(
        address indexed provider,
        bytes32 indexed endpoint,
        int[] curve
    );

    DatabaseInterface public db;

    constructor(address c) Upgradable(c) public {
        _updateDependencies();
    }

    function _updateDependencies() internal {
        address databaseAddress = coordinator.getContract("DATABASE");
        db = DatabaseInterface(databaseAddress);
    }

    /// @dev initiates a provider.
    /// If no address->Oracle mapping exists, Oracle object is created
    /// @param publicKey unique id for provider. used for encyrpted key swap for subscription endpoints
    /// @param title name
    function initiateProvider(
        uint256 publicKey,
        bytes32 title
    )
        public
        returns (bool)
    {
        require(!isProviderInitiated(msg.sender));
        createOracle(msg.sender, publicKey, title);
        addOracle(msg.sender);
        emit NewProvider(msg.sender, title);
        return true;
    }

    /// @dev initiates an endpoint specific provider curve
    /// If oracle[specfifier] is uninitialized, Curve is mapped to endpoint
    /// @param endpoint specifier of endpoint. currently "smart_contract" or "socket_subscription"
    /// @param curve flattened array of all segments, coefficients across all polynomial terms, [e0,l0,c0,c1,c2,...]
    function initiateProviderCurve(
        bytes32 endpoint,
        int256[] curve
    )
        public
        returns (bool)
    {
        // Provider must be initiated
        require(isProviderInitiated(msg.sender));
        // Can't reset their curve
        require(getCurveUnset(msg.sender, endpoint));

        setCurve(msg.sender, endpoint, curve);        
        db.pushBytesArray(keccak256(abi.encodePacked('oracles', msg.sender, 'endpoints')), endpoint);
        emit NewCurve(msg.sender, endpoint, curve);

        return true;
    }

    // Sets provider data
    function setProviderParameter(bytes32 key, bytes32 value) public {
        // Provider must be initiated
        require(isProviderInitiated(msg.sender));

        if(!isProviderParamInitialized(msg.sender, key)){
            // initialize this provider param
            db.setNumber(keccak256(abi.encodePacked('oracles', msg.sender, 'is_param_set', key)), 1);
            db.pushBytesArray(keccak256(abi.encodePacked('oracles', msg.sender, 'providerParams')), key);
        }
        db.setBytes32(keccak256(abi.encodePacked('oracles', msg.sender, 'providerParams', key)), value);
    }

    // Gets provider data
    function getProviderParameter(address provider, bytes32 key) public view returns (bytes32){
        // Provider must be initiated
        require(isProviderInitiated(provider));
        require(isProviderParamInitialized(provider, key));
        return db.getBytes32(keccak256(abi.encodePacked('oracles', provider, 'providerParams', key)));
    }

    // Gets keys of all provider params
    function getAllProviderParams(address provider) public view returns (bytes32[]){
        // Provider must be initiated
        require(isProviderInitiated(provider));
        return db.getBytesArray(keccak256(abi.encodePacked('oracles', provider, 'providerParams')));
    }

    // Set endpoint specific parameters for a given endpoint
    function setEndpointParams(bytes32 endpoint, bytes32[] endpointParams) public {
        // Provider must be initiated
        require(isProviderInitiated(msg.sender));
        // Can't set endpoint params on an unset provider
        require(!getCurveUnset(msg.sender, endpoint));

        db.setBytesArray(keccak256(abi.encodePacked('oracles', msg.sender, 'endpointParams', endpoint)), endpointParams);
    }

    // get endpoint specific parameters for a given endpoint
    function getEndpointParams(address provider, bytes32 endpoint) public view returns (bytes32[]) {
        // Provider, endpoint must be initiated
        require(isProviderInitiated(msg.sender));
        require(!getCurveUnset(msg.sender, endpoint));

        return db.getBytesArray(keccak256(abi.encodePacked('oracles', provider, 'endpointParams', endpoint)));
    }

    /// @return public key
    function getProviderPublicKey(address provider) public view returns (uint256) {
        return getPublicKey(provider);
    }

    /// @return oracle name
    function getProviderTitle(address provider) public view returns (bytes32) {
        return getTitle(provider);
    }


    /// @dev get curve paramaters from oracle
    function getProviderCurve(
        address provider,
        bytes32 endpoint
    )
        public
        view
        returns (int[])
    {
        require(!getCurveUnset(provider, endpoint));
        return db.getIntArray(keccak256(abi.encodePacked('oracles', provider, 'curves', endpoint)));
    }

    function getProviderCurveLength(address provider, bytes32 endpoint) public view returns (uint256){
        require(!getCurveUnset(provider, endpoint));
        return db.getIntArray(keccak256(abi.encodePacked('oracles', provider, 'curves', endpoint))).length;
    }

    /// @dev is provider initiated
    /// @param oracleAddress the provider address
    /// @return Whether or not the provider has initiated in the Registry.
    function isProviderInitiated(address oracleAddress) public view returns (bool) {
        return getProviderTitle(oracleAddress) != 0;
    }

    /*** STORAGE FUNCTIONS ***/
    /// @dev get public key of provider
    function getPublicKey(address provider) public view returns (uint256) {
        return db.getNumber(keccak256(abi.encodePacked("oracles", provider, "publicKey")));
    }

    /// @dev get title of provider
    function getTitle(address provider) public view returns (bytes32) {
        return db.getBytes32(keccak256(abi.encodePacked("oracles", provider, "title")));
    }

    /// @dev get the endpoints of a provider
    function getProviderEndpoints(address provider) public view returns (bytes32[]) {
        return db.getBytesArray(keccak256(abi.encodePacked("oracles", provider, "endpoints")));
    }

    /// @dev get all endpoint params
    function getEndPointParams(address provider, bytes32 endpoint) public view returns (bytes32[]) {
        return db.getBytesArray(keccak256(abi.encodePacked('oracles', provider, 'endpointParams', endpoint)));
    }

    function getCurveUnset(address provider, bytes32 endpoint) public view returns (bool) {
        return db.getIntArrayLength(keccak256(abi.encodePacked('oracles', provider, 'curves', endpoint))) == 0;
    }

    /// @dev get overall number of providers
    function getOracleIndexSize() public view returns (uint256) {
        return db.getAddressArrayLength(keccak256(abi.encodePacked('oracleIndex')));
    }

    /// @dev get provider address by index
    function getOracleAddress(uint256 index) public view returns (address) {
        return db.getAddressArrayIndex(keccak256(abi.encodePacked('oracleIndex')), index);
    }

    /// @dev get all oracle addresses
    function getAllOracles() external view returns (address[]) {
        return db.getAddressArray(keccak256(abi.encodePacked('oracleIndex')));
    }

    ///  @dev add new provider to mapping
    function createOracle(address provider, uint256 publicKey, bytes32 title) private {
        db.setNumber(keccak256(abi.encodePacked('oracles', provider, "publicKey")), uint256(publicKey));
        db.setBytes32(keccak256(abi.encodePacked('oracles', provider, "title")), title);
    }

    /// @dev add new provider address to oracles array
    function addOracle(address provider) private {
        db.pushAddressArray(keccak256(abi.encodePacked('oracleIndex')), provider);
    }

    /// @dev initialize new curve for provider
    /// @param provider address of provider
    /// @param endpoint endpoint specifier
    /// @param curve flattened array of all segments, coefficients across all polynomial terms, [l0,c0,c1,c2,..., ck, e0, ...]
    function setCurve(
        address provider,
        bytes32 endpoint,
        int[] curve
    )
        private
    {
        uint prevEnd = 1;
        uint index = 0;

        // Validate the curve
        while ( index < curve.length ) {
            // Validate the length of the piece
            int len = curve[index];
            require(len > 0);

            // Validate the end index of the piece
            uint endIndex = index + uint(len) + 1;
            require(endIndex < curve.length);

            // Validate that the end is continuous
            int end = curve[endIndex];
            require(uint(end) > prevEnd);

            prevEnd = uint(end);
            index += uint(len) + 2; 
        }

        db.setIntArray(keccak256(abi.encodePacked('oracles', provider, 'curves', endpoint)), curve);
    }

    // Determines whether this parameter has been initialized
    function isProviderParamInitialized(address provider, bytes32 key) private view returns (bool){
        uint256 val = db.getNumber(keccak256(abi.encodePacked('oracles', provider, 'is_param_set', key)));
        return (val == 1) ? true : false;
    }

    /*************************************** STORAGE ****************************************
    * 'oracles', provider, 'endpoints' => {bytes32[]} array of endpoints for this oracle
    * 'oracles', provider, 'endpointParams', endpoint => {bytes32[]} array of params for this endpoint
    * 'oracles', provider, 'curves', endpoint => {uint[]} curve array for this endpoint
    * 'oracles', provider, 'is_param_set', key => {uint} Is this provider parameter set (0/1)
    * 'oracles', provider, "publicKey" => {uint} public key for this oracle
    * 'oracles', provider, "title" => {bytes32} title of this oracle
    ****************************************************************************************/
}
