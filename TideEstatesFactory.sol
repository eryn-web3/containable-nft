pragma solidity >=0.6.0 <=0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


interface ITideEstatesItem is IERC721 {
    function getPrice(uint tokenId) external view returns(uint);
}


contract TideEstatesApartment is IERC721Receiver {
    uint[] public items;
    ITideEstatesItem public _nft;
    bool public _listed;
    string public _URI;
    address public _factory;
    address public _owner;

    constructor(address nft, uint[] memory _items, address owner) public {
        _nft = ITideEstatesItem(nft);
        items = _items;
        _factory = msg.sender;

        transferOwnership(owner);
    }
    
    modifier onlyOwner() {
        require(msg.sender == _owner || msg.sender == _factory, "You must be the owner");
        _;
    }
    
    function transferOwnership(address owner) public onlyOwner {
        _owner = owner;
    }
    
    function putItems(uint[] memory _items) external onlyOwner {
        for (uint i = 0; i < _items.length; i++) {
            _nft.safeTransferFrom(msg.sender, address(this), _items[i]);
            items.push(_items[i]);
        }
    }
    
    function takeItem(uint id) external onlyOwner {
        bool found;
        for (uint i = 0; i < items.length; i++) {
            if (!found && items[i] == id) {
                _nft.safeTransferFrom(address(this), msg.sender, id);
                found = true;
            }
            
            if (found && i < items.length - 1) {
                items[i] = items[i + 1];
            }
        }
        require(found, "Item not found");
        items.pop();
    }
    
    function count() external view returns(uint) {
        return items.length;
    }
    
    function unpack() external onlyOwner {
        for (uint i = 0; i < items.length; i++) {
            IERC721(_nft).safeTransferFrom(address(this), msg.sender, items[i]);
            items.pop();
        }
    }
    
    function transferTo(address to) external onlyOwner {
        transferOwnership(to);
    }
    
    function setListed(bool listed_) external onlyOwner {
        _listed = listed_;
    }
    
    function setURI(string memory URI_) external onlyOwner {
        _URI = URI_;
    }
    
    function getPrice() public view returns(uint) {
        uint _price;
    
        for (uint i = 0; i < items.length; i++) {
            _price = _price + _nft.getPrice(items[i]);
        }
        return _price;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}


contract TideEstatesNFTFactory is Context, Ownable {
    mapping(address => address[]) userToItems;
    mapping(address => address) itemToUser;
    address private _nft;
    address[] private boxes;
    address private _feeAddress;
    uint private _fee;

    event apartmentCreated(
        address apartment
    );

    constructor(address nft, address feeAddress_, uint fee_) public {
        _nft = nft;
        _feeAddress = feeAddress_;
        _fee = fee_;
    }
    
    function feeAddress() public view returns(address) {
        return _feeAddress;
    }
    
    function setFeeAddress(address feeAddress_) external onlyOwner {
        _feeAddress = feeAddress_;
    }
    
    function fee() public view returns(uint) {
        return _fee;
    }
    
    function setFee(uint fee_) external onlyOwner {
        _fee = fee_;
    }

    function createApartment(uint[] memory items) external {
        TideEstatesApartment apartment = new TideEstatesApartment(_nft, items, msg.sender);
        
        for (uint i = 0; i < items.length; i++) {
            IERC721(_nft).safeTransferFrom(msg.sender, address(apartment), items[i]);
        }
        
        itemToUser[address(apartment)] = msg.sender;
        userToItems[msg.sender].push(address(apartment));
        
        boxes.push(address(apartment));

        emit apartmentCreated(address(apartment));
    }
    
    function nft() external view returns(address) {
        return _nft;
    }
    
    function ownerOf(address box) external view returns(address) {
        return itemToUser[box];
    }
    
    function count() external view returns(uint) {
        return boxes.length;
    }
    
    function getApartment(uint id) external view returns(address) {
        require (id < boxes.length, "No item");
        return boxes[id];
    }
    
    function getUserApartmentsCount(address user) external view returns(uint) {
        return userToItems[user].length;
    }
    
    function getUserApartment(address user, uint id) external view returns(address) {
        return userToItems[user][id];
    }
    
    event Purchase(address from, address to, address item, uint price);
    
    function buy(address apartment) external payable {
        address payable seller = payable(itemToUser[apartment]);
        address payable buyer = payable(msg.sender);
        address payable feeReceiver = payable(_feeAddress);
        
        uint price = TideEstatesApartment(apartment).getPrice();
        
        require ((seller != address(0)) && (buyer != seller), "You can't buy your own");
        require (msg.value >= price, "The amount is lower");
   
        uint feeAmount = price * _fee / 10000;
        
        seller.transfer(price - feeAmount);
        feeReceiver.transfer(feeAmount);
        
        itemToUser[apartment] = buyer;
        
        userToItems[buyer].push(apartment);
        
        bool removed = false;
        for (uint i = 0; i < userToItems[seller].length; i++) {
            if (!removed && userToItems[seller][i] == apartment) {
                removed = true;
            }
            
            if (removed && i < userToItems[seller].length - 1) {
                userToItems[seller][i] = userToItems[seller][i + 1];
            }
        }
        require(removed, "Error occurred");
        userToItems[seller].pop();
        
        TideEstatesApartment(apartment).transferOwnership(buyer);
        
        if (msg.value > price) {
            buyer.transfer(msg.value - price);
        }
        
        emit Purchase(seller, buyer, apartment, price);
        
    }
}