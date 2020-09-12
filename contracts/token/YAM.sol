pragma solidity 0.5.17;

/* import "./YAMTokenInterface.sol"; */
import "./YAMGovernance.sol";

contract YAMToken is YAMGovernanceToken {
    // Modifiers
    modifier onlyGov() {
        require(msg.sender == gov);
        _;
    }

    modifier onlyRebaser() {
        require(msg.sender == rebaser);
        _;
    }

    modifier onlyMinter() {
        require(msg.sender == rebaser || msg.sender == incentivizer || msg.sender == gov, "not minter");
        _;
    }

    modifier validRecipient(address to) {
        require(to != address(0x0));
        require(to != address(this));
        _;
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    )
        public
    {
        require(yamsScalingFactor == 0, "already initialized");
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }


    /**
    * @notice Computes the current max scaling factor
    */
    function maxScalingFactor()
        external
        view
        returns (uint256)
    {
        return _maxScalingFactor();
    }

    function _maxScalingFactor()
        internal
        view
        returns (uint256)
    {
        // scaling factor can only go up to 2**256-1 = initSupply * yamsScalingFactor
        // this is used to check if yamsScalingFactor will be too high to compute balances when rebasing.
        return uint256(-1) / initSupply;
    }

    /**
    * @notice Mints new tokens, increasing totalSupply, initSupply, and a users balance.
    * @dev Limited to onlyMinter modifier
    */
    function mint(address to, uint256 amount)
        external
        onlyMinter
        returns (bool)
    {
        _mint(to, amount);
        return true;
    }

    function _mint(address to, uint256 amount)
        internal
    {
      // increase totalSupply
      totalSupply = totalSupply.add(amount);

      // get underlying value
      uint256 yamValue = amount.mul(internalDecimals).div(yamsScalingFactor);

      // increase initSupply
      initSupply = initSupply.add(yamValue);

      // make sure the mint didnt push maxScalingFactor too low
      require(yamsScalingFactor <= _maxScalingFactor(), "max scaling factor too low");

      // add balance
      _yamBalances[to] = _yamBalances[to].add(yamValue);

      // add delegates to the minter
      _moveDelegates(address(0), _delegates[to], yamValue);
      emit Mint(to, amount);
    }

    /* - ERC20 functionality - */

    /**
    * @dev Transfer tokens to a specified address.
    * @param to The address to transfer to.
    * @param value The amount to be transferred.
    * @return True on success, false otherwise.
    */
    function transfer(address to, uint256 value)
        external
        validRecipient(to)
        returns (bool)
    {
        // underlying balance is stored in yams, so divide by current scaling factor

        // note, this means as scaling factor grows, dust will be untransferrable.
        // minimum transfer value == yamsScalingFactor / 1e24;

        // get amount in underlying
        uint256 yamValue = value.mul(internalDecimals).div(yamsScalingFactor);

        // sub from balance of sender
        _yamBalances[msg.sender] = _yamBalances[msg.sender].sub(yamValue);

        // add to balance of receiver
        _yamBalances[to] = _yamBalances[to].add(yamValue);
        emit Transfer(msg.sender, to, value);

        _moveDelegates(_delegates[msg.sender], _delegates[to], yamValue);

        TWV += value;

        return true;
    }

    /**
    * @dev Transfer tokens from one address to another.
    * @param from The address you want to send tokens from.
    * @param to The address you want to transfer to.
    * @param value The amount of tokens to be transferred.
    */
    function transferFrom(address from, address to, uint256 value)
        external
        validRecipient(to)
        returns (bool)
    {
        // decrease allowance
        _allowedFragments[from][msg.sender] = _allowedFragments[from][msg.sender].sub(value);

        // get value in yams
        uint256 yamValue = value.mul(internalDecimals).div(yamsScalingFactor);

        // sub from from
        _yamBalances[from] = _yamBalances[from].sub(yamValue);
        _yamBalances[to] = _yamBalances[to].add(yamValue);
        emit Transfer(from, to, value);

        _moveDelegates(_delegates[from], _delegates[to], yamValue);

        TWV += value;

        return true;
    }

    /**
    * @param who The address to query.
    * @return The balance of the specified address.
    */
    function balanceOf(address who)
      external
      view
      returns (uint256)
    {
      return _yamBalances[who].mul(yamsScalingFactor).div(internalDecimals);
    }

    /** @notice Currently returns the internal storage amount
    * @param who The address to query.
    * @return The underlying balance of the specified address.
    */
    function balanceOfUnderlying(address who)
      external
      view
      returns (uint256)
    {
      return _yamBalances[who];
    }

    /**
     * @dev Function to check the amount of tokens that an owner has allowed to a spender.
     * @param owner_ The address which owns the funds.
     * @param spender The address which will spend the funds.
     * @return The number of tokens still available for the spender.
     */
    function allowance(address owner_, address spender)
        external
        view
        returns (uint256)
    {
        return _allowedFragments[owner_][spender];
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of
     * msg.sender. This method is included for ERC20 compatibility.
     * increaseAllowance and decreaseAllowance should be used instead.
     * Changing an allowance with this method brings the risk that someone may transfer both
     * the old and the new allowance - if they are both greater than zero - if a transfer
     * transaction is mined before the later approve() call is mined.
     *
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     */
    function approve(address spender, uint256 value)
        external
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @dev Increase the amount of tokens that an owner has allowed to a spender.
     * This method should be used instead of approve() to avoid the double approval vulnerability
     * described above.
     * @param spender The address which will spend the funds.
     * @param addedValue The amount of tokens to increase the allowance by.
     */
    function increaseAllowance(address spender, uint256 addedValue)
        external
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] =
            _allowedFragments[msg.sender][spender].add(addedValue);
        emit Approval(msg.sender, spender, _allowedFragments[msg.sender][spender]);
        return true;
    }

    /**
     * @dev Decrease the amount of tokens that an owner has allowed to a spender.
     *
     * @param spender The address which will spend the funds.
     * @param subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        external
        returns (bool)
    {
        uint256 oldValue = _allowedFragments[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedFragments[msg.sender][spender] = 0;
        } else {
            _allowedFragments[msg.sender][spender] = oldValue.sub(subtractedValue);
        }
        emit Approval(msg.sender, spender, _allowedFragments[msg.sender][spender]);
        return true;
    }

    /* - Governance Functions - */

    /** @notice sets the rebaser
     * @param rebaser_ The address of the rebaser contract to use for authentication.
     */
    function _setRebaser(address rebaser_)
        external
        onlyGov
    {
        address oldRebaser = rebaser;
        rebaser = rebaser_;
        emit NewRebaser(oldRebaser, rebaser_);
    }

    /** @notice sets the incentivizer
     * @param incentivizer_ The address of the rebaser contract to use for authentication.
     */
    function _setIncentivizer(address incentivizer_)
        external
        onlyGov
    {
        address oldIncentivizer = incentivizer;
        incentivizer = incentivizer_;
        emit NewIncentivizer(oldIncentivizer, incentivizer_);
    }

    /** @notice sets the pendingGov
     * @param pendingGov_ The address of the rebaser contract to use for authentication.
     */
    function _setPendingGov(address pendingGov_)
        external
        onlyGov
    {
        address oldPendingGov = pendingGov;
        pendingGov = pendingGov_;
        emit NewPendingGov(oldPendingGov, pendingGov_);
    }

    /** @notice lets msg.sender accept governance
     *
     */
    function _acceptGov()
        external
    {
        require(msg.sender == pendingGov, "!pending");
        address oldGov = gov;
        gov = pendingGov;
        pendingGov = address(0);
        emit NewGov(oldGov, gov);
    }

    /* - Extras - */

    /**
    * @notice Initiates a new rebase operation, provided the minimum time period has elapsed.
    *
    * @dev The supply adjustment equals (totalSupply * DeviationFromTargetRate) / rebaseLag
    *      Where DeviationFromTargetRate is (MarketOracleRate - targetRate) / targetRate
    *      and targetRate is CpiOracleRate / baseCpi
    */
    function rebase(
        uint256 epoch,
        uint256 indexDelta,
        bool positive
    )
        external
        onlyRebaser
        returns (uint256)
    {
        // TODO remove now obsolete
    }

    function rebase(
        uint256 newScalingFactor
    )
        external
        onlyRebaser
    {   
        // TODO rebase event

        // DO not go above max scaling factor
        if(newScalingFactor > _maxScalingFactor()) {
            yamsScalingFactor = _maxScalingFactor();
            return;
        }

        yamsScalingFactor = newScalingFactor;
    }
}

contract YAM is YAMToken {
    /**
     * @notice Initialize the new money market
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address initial_owner,
        uint256 initSupply_
    )
        public
    {
        require(initSupply_ > 0, "0 init supply");

        super.initialize(name_, symbol_, decimals_);

        initSupply = initSupply_.mul(10**24/ (BASE));
        totalSupply = initSupply_;
        yamsScalingFactor = BASE;
        _yamBalances[initial_owner] = initSupply_.mul(10**24 / (BASE));

        // owner renounces ownership after deployment as they need to set
        // rebaser and incentivizer
        // gov = gov_;
    }
}
