// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface InterfaceErc20 {
    function name() external view returns(string memory);

    function symbol() external view returns(string memory);

    function decimals() external pure returns(uint);

    function totalSupply() external view returns(uint256);

    function balanceOf(address _owner) external view returns(uint256);

    function allowance(address _owner, address _spender) external view returns(uint256);

    function transfer(address _to, uint256 _value) external returns(bool);

    function transferFrom(address _from, address _to, uint256 _value) external returns(bool);

    function approve(address _spender, uint256 _value) external returns(bool);

    event Transfer(address indexed _from, address indexed _to, uint _value);

    event Approve(address indexed _sender, address indexed _spender, uint _value);
}


contract Erc20 is InterfaceErc20 {
    string internal _name;
    string internal _symbol;

    address internal owner;

    uint internal total;

    mapping(address => uint256) internal balances;
    mapping(address => mapping(address => uint256)) internal allowances;

    constructor(
        string memory name_,
        string memory symbol_,
        address exchanger_,
        uint initialTotal
    ) {
        owner = msg.sender;

        _name = name_;
        _symbol = symbol_;

        mint(exchanger_, initialTotal);
    }

    modifier checkTokenSufficiency(address _from, uint _value) {
        // модификатор для проверки достаточности количества токенов для совершения операции
        require(_value > 0 && balanceOf(_from) >= _value, "Incorrect value for transaction!");
        _;
    }

    modifier allowOnlyToOwner() {
        // модификатор для ограничения доступа к функции для всех кроме владельца
        require(msg.sender == owner, "This operation is allowed only for owner!");
        _;
    }

    function name() external view returns(string memory) {
        return _name;
    }

    function symbol() external view returns(string memory) {
        return _symbol;
    }

    function decimals() external pure returns(uint) {
        return 18;  // 1 wei
    }

    function totalSupply() external view returns(uint256) {
        return total;
    }

    function balanceOf(address _owner) public view returns(uint256) {
        return balances[_owner];
    }

    function allowance(address _owner, address _spender) external view returns(uint256) {
        return allowances[_owner][_spender];
    }

    function _beforeTokenTransfer(address _from, address _to, uint _value) internal virtual returns(bool) {
        // служебная функция для определения возможности осуществления перевода
        return true;
    }

    function _beforeTokenApprove(address _sender, address _spender, uint _value) internal virtual returns(bool) {
        // служебная функция для определения возможности разрешения передачи токенов
        return true;
    }

    function transfer(address _to, uint256 _value) external checkTokenSufficiency(msg.sender, _value) returns(bool) {
        address _from = msg.sender;
        bool _status = _transfer(_from, _to, _value);
        return _status;
    }

    function transferFrom(address _from, address _to, uint256 _value) external checkTokenSufficiency(_from, _value) returns(bool) {
        require(allowances[_from][_to] >= _value, "No allowance provided for this transaction!");
        bool _status = _transfer(_from, _to, _value);
        if (_status) {
            allowances[_from][_to] -= _value;
        }
        return _status;
    }

    function _transfer(address _from, address _to, uint256 _value) internal returns(bool) {
        bool _status = _beforeTokenTransfer(_from, _to, _value);

        if (_status) {
            balances[_from] -= _value;
            balances[_to] += _value;

            emit Transfer(_from, _to, _value);
        }

        return _status;
    }

    function approve(address _spender, uint256 _value) external returns(bool) {
        address _sender = msg.sender;

        bool _status = _beforeTokenApprove(_sender, _spender, _value);

        if (_status) {
            allowances[_sender][_spender] = _value;
            emit Approve(_sender, _spender, _value);
        }

        return _status;
    }

    function mint(address _exchanger, uint _value) public allowOnlyToOwner {
        // ввод в оборот определенного количества валюты
        _beforeTokenTransfer(address(0), _exchanger, _value);

        balances[_exchanger] += _value;
        total += _value;

        emit Transfer(address(0), _exchanger, _value);
    }
}


contract DonationToken is Erc20 {
    // [address, address, ...]
    address[] public membersRegistry;
    // {address: true, ...}
    mapping(address => bool) public membersStatus;

    // {address: ["guitar", "balalaika", ...]}
    mapping(address => string[]) internal _donateNeedsNames;
    // {address: {"guitar": {"total": 300, "index": 0},
    //            "balalaika": {"total": 500, "index": 1}}}
    mapping(address => mapping(string => mapping(string => uint256))) internal _donateNeeds;
    // {address: 900}
    mapping(address => uint256) internal _donateBalances;

    constructor(address _exchanger) Erc20("DonationToken", "DNTT", _exchanger, 300) {}

    modifier allowOnlyToMember() {
        // модификатор для ограничения доступа к функции для всех кроме участника объединения
        require(membersStatus[msg.sender], "This operation is allowed only for member!");
        _;
    }

    function donateNeedsNames(address _member) external view returns(string[] memory) {
        return _donateNeedsNames[_member];
    }

    function donateNeed(address _member, string memory _needName) external view returns(uint256) {
        return _donateNeeds[_member][_needName]["total"];
    }

    function donateBalance(address _member) external view returns(uint256) {
        return _donateBalances[_member];
    }

    function registerDonateNeeds(string memory _needName, uint _needs) external allowOnlyToMember {
        // регистрация сбора на конкретную цель
        require(_needs > 0, "Needs should be > 0!");
        require(bytes(_needName).length > 0, "Need name should not be blank!");

        address _member = msg.sender;

        _donateNeedsNames[_member].push(_needName);
        uint _indexNeed = _donateNeedsNames[_member].length - 1;

        _donateNeeds[_member][_needName]["index"] = _indexNeed;
        _donateNeeds[_member][_needName]["total"] = _needs;

        emit NeedsRegister(_member, _needName);
    }

    function deleteDonateNeeds(string memory _needName) external allowOnlyToMember {
        // удаление сбора на конкретую цель
        address _member = msg.sender;

        require(_donateNeeds[_member][_needName]["total"] != 0, "Should be existing donate need!");

        uint _index = _donateNeeds[_member][_needName]["index"];
        _removeNeedFromNeedsNames(_member, _index);

        // ['total'] == 0 for deleted or not created needs
        _donateNeeds[_member][_needName]["total"] = 0;

        emit NeedsDeletion(_member, _needName);
    }

    function donate(uint _value) external checkTokenSufficiency(msg.sender, _value) returns(bool) {
        // донат для одного рандомного нуждающегося
        require(membersRegistry.length > 0, "No members yet!");

        address _from = msg.sender;

        uint _index = uint(block.number % membersRegistry.length);
        address _to = membersRegistry[_index];

        bool _status = _transfer(_from, _to, _value);
        if (_status)
            _donateBalances[_to] += _value;
        return _status;
    }

    function donateAll(uint _value) external checkTokenSufficiency(msg.sender, _value) returns(bool) {
        // донат для всех нуждающихся
        require(membersRegistry.length > 0, "No members yet!");
        require(_value >= membersRegistry.length, "Members number is more than donation sum!");

        address _from = msg.sender;
        uint _value_per_member = _value / membersRegistry.length;
        bool _status_all = true;

        // осуществление перевода
        for (uint i; i < membersRegistry.length; i++) {
            address _to = membersRegistry[i];
            bool _status = _transfer(_from, _to, _value_per_member);
            if (_status)
                _donateBalances[_to] += _value_per_member;
            _status_all = _status_all && _status;
        }

        return _status_all;
    }

    function registerMember(address _newMember) external allowOnlyToOwner {
        // регистрация участника
        require(membersStatus[_newMember] == false, "This needy is already a member!");
        membersRegistry.push(_newMember);
        membersStatus[_newMember] = true;
        emit MemberRegister(_newMember);
    }

    function disableMember(address _member) external allowOnlyToOwner {
        // деактивация участника
        require(membersStatus[_member] == true, "This needy is not a member!");
        for (uint _index = 0; _index < membersRegistry.length - 1; _index++) {
            if (membersRegistry[_index] == _member) {
                _removeMemberFromRegistry(_index);
            }
        }

        membersStatus[_member] = false;

        emit MemberDisabled(_member);
    }

    function _removeMemberFromRegistry(uint _index) internal {
        require(_index < membersRegistry.length, "Index out of registry!");

        for (uint i = _index; i < membersRegistry.length - 1; i++) {
            membersRegistry[i] = membersRegistry[i + 1];
        }

        membersRegistry.pop();
    }

    function _removeNeedFromNeedsNames(address _member, uint _index) internal {
        require(_index < _donateNeedsNames[_member].length, "Index out of array!");

         for (uint i = _index; i < _donateNeedsNames[_member].length - 1; i++) {
            _donateNeedsNames[_member][i] = _donateNeedsNames[_member][i + 1];
        }

        _donateNeedsNames[_member].pop();
    }

    event NeedsRegister(address indexed _member, string _needName);
    event NeedsDeletion(address indexed _member, string _needName);

    event MemberRegister(address indexed _member);
    event MemberDisabled(address indexed _member);
}


contract DonationExchanger {
    InterfaceErc20 public token;
    address payable public owner;

    event Buy(address indexed _buyer, uint _value);
    event Sell(address indexed _seller, uint _value);

    constructor() {
        token = new DonationToken(address(this));
        owner = payable(msg.sender);
    }

    modifier checkTokenSufficiency(address _from, uint _value) {
        // модификатор для проверки достаточности количества токенов для совершения операции
        require(_value > 0 && token.balanceOf(_from) >= _value, "Incorrect value for transaction!");
        _;
    }

    function sell(uint _value) public checkTokenSufficiency(msg.sender, _value) {
        // продажа токенов обменнику
        address _from = msg.sender;
        address _to = address(this);

        uint _allowance = token.allowance(_from, address(this));
        require(_allowance >= _value, "No allowance!");

        token.transferFrom(_from, _to, _value);
        payable(_from).transfer(_value);

        emit Sell(_from, _value);
    }

    receive() external payable checkTokenSufficiency(address(this), msg.value) {
        // продажа обменником токенов
        address _to = msg.sender;
        uint _value = msg.value;

        token.transfer(_to, _value);

        emit Buy(_to, _value);
    }
}