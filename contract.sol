// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/*
    This file implements an ERC20 token called "Grok" with several security and usability improvements:
      1. Mitigates the approval race condition by requiring a reset to zero before re-approval.
      2. Enforces a maximum supply cap to prevent minting above a predetermined limit.
      3. Disables renouncing ownership to prevent accidental loss of owner privileges.
      4. Adds recovery functions to allow the owner to retrieve mistakenly sent ERC20 tokens or ETH.
      5. Provides extensive inline comments for clarity.
*/

interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     * Returns a boolean value indicating whether the operation succeeded.
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` is allowed to spend
     * on behalf of `owner` through {transferFrom}. This is zero by default.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     * Returns a boolean value indicating whether the operation succeeded.
     * IMPORTANT: To mitigate the race condition, the allowance must first be set to zero.
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the allowance mechanism.
     * `amount` is then deducted from the caller's allowance.
     * Returns a boolean value indicating whether the operation succeeded.
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    // Event emitted when tokens are moved from one account to another.
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    // Event emitted when the allowance of a `spender` for an `owner` is set by a call to {approve}.
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
    // Returns the name of the token.
    function name() external view returns (string memory);
    
    // Returns the symbol of the token.
    function symbol() external view returns (string memory);
    
    // Returns the number of decimals used to get its user representation.
    function decimals() external view returns (uint8);
}

/*
    Context provides information about the current execution context, including the
    sender of the transaction and its data. This is used to abstract away direct references
    to msg.sender and msg.data, which can be useful for meta-transactions.
*/
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/*
    ERC20 implements the standard ERC20 token functionality with the following modifications:
      - It uses 9 decimals (non-standard, but intentional).
      - The `approve` function requires a reset to zero to mitigate the race condition.
      - A maximum supply cap is enforced in the `_mint` function.
*/
contract ERC20 is Context, IERC20, IERC20Metadata {
    // Mapping from account addresses to their balances.
    mapping(address => uint256) private _balances;
    
    // Mapping from owner addresses to spender addresses and allowances.
    mapping(address => mapping(address => uint256)) private _allowances;
    
    // Total supply of tokens.
    uint256 private _totalSupply;
    
    // Token name and symbol.
    string private _name;
    string private _symbol;
    
    // Maximum total supply cap (adjustable as needed).
    uint256 public constant MAX_SUPPLY = 1_000_000_000_000 * (10 ** 9);

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    // Returns the token name.
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    // Returns the token symbol.
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    // Returns the balance of a given account.
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    // Transfers tokens from the caller to `recipient`.
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    // Returns the number of decimals used for token display. Here, it's set to 9.
    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    // Returns the total supply of tokens.
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    // Returns the current allowance for a spender on behalf of an owner.
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /*
        Approves `spender` to transfer `amount` tokens on behalf of the caller.
        To mitigate the approval race condition, we require that the current allowance is either zero
        or the new allowance is zero. Users are encouraged to use increaseAllowance/decreaseAllowance.
    */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        require(
            _allowances[_msgSender()][spender] == 0 || amount == 0,
            "ERC20: must reset allowance to zero first"
        );
        _approve(_msgSender(), spender, amount);
        return true;
    }

    // Transfers tokens from `sender` to `recipient` using the allowance mechanism.
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        // If allowance is maximum (infinite), skip deduction.
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
            unchecked {
                _approve(sender, _msgSender(), currentAllowance - amount);
            }
        }
        _transfer(sender, recipient, amount);
        return true;
    }

    // Increases the allowance granted to `spender` by the caller.
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    // Decreases the allowance granted to `spender` by the caller.
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }
        return true;
    }

    /*
        Internal function to transfer tokens from `sender` to `recipient`.
        Ensures that the sender and recipient addresses are valid and that the sender has sufficient balance.
        It also calls hooks before and after the transfer.
    */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        
        _beforeTokenTransfer(sender, recipient, amount);
        
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;
        
        emit Transfer(sender, recipient, amount);
        _afterTokenTransfer(sender, recipient, amount);
    }

    /*
        Internal minting function that creates new tokens.
        It ensures that the maximum supply cap is not exceeded.
    */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");
        // Enforce the maximum supply cap.
        require(_totalSupply + amount <= MAX_SUPPLY, "ERC20: max supply exceeded");
        
        _beforeTokenTransfer(address(0), account, amount);
        
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
        
        _afterTokenTransfer(address(0), account, amount);
    }

    /*
        Internal burning function that destroys tokens from `account`.
        It decreases both the account's balance and the total supply.
    */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");
        
        _beforeTokenTransfer(account, address(0), amount);
        
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;
        
        emit Transfer(account, address(0), amount);
        _afterTokenTransfer(account, address(0), amount);
    }

    // Internal function to set the allowance for a spender.
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // Hook called before any transfer of tokens. Can be overridden in derived contracts.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    // Hook called after any transfer of tokens. Can be overridden in derived contracts.
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}

/*
    Ownable provides a basic access control mechanism, where an account (the owner)
    has exclusive access to specific functions.
    Modifications:
      - Disables renouncing ownership to prevent accidental loss of control.
*/
contract Ownable is Context {
    address private _owner;
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    // The deployer is set as the initial owner.
    constructor() {
        _transferOwnership(_msgSender());
    }
    
    // Modifier to restrict function access to the owner.
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
    
    // Returns the current owner's address.
    function owner() public view virtual returns (address) {
        return _owner;
    }
    
    /*
        Overrides renounceOwnership to disable it.
        This prevents the contract from being accidentally rendered ownerless.
    */
    function renounceOwnership() public virtual onlyOwner {
        revert("Ownable: renouncing ownership is disabled");
    }
    
    // Allows the owner to transfer ownership to a new address.
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }
    
    // Internal function to set a new owner and emit an event.
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

/*
    GROK token contract which inherits from ERC20 and Ownable.
    It mints the initial supply to the deployer and includes recovery functions.
*/
contract GROK is ERC20, Ownable {
    constructor () ERC20("Grok", "GROK") {
        // Mint the initial supply to the deployer.
        _mint(msg.sender, 1_000_000_000_000 * (10 ** 9));
    }
    
    /*
        Allows the owner to recover any ERC20 tokens accidentally sent to this contract.
        The contract's own tokens cannot be recovered to avoid abuse.
    */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(this), "Cannot recover own tokens");
        IERC20(tokenAddress).transfer(owner(), tokenAmount);
    }
    
    /*
        Allows the owner to recover any ETH accidentally sent to this contract.
    */
    function recoverETH() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
    
    // Fallback function to accept ETH deposits.
    receive() external payable {}
}
