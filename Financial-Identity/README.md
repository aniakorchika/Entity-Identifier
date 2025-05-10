# LEI Registry Smart Contract

A Clarity smart contract for managing Legal Entity Identifiers (LEIs) on the Stacks blockchain.

## Overview

This smart contract provides a comprehensive system for registering, validating, and managing Legal Entity Identifiers (LEIs) - the 20-character alphanumeric codes that uniquely identify legal entities participating in financial transactions globally.

The contract enables authorized administrators to register new LEIs, while allowing LEI owners to manage their identifiers, including renewal, information updates, and ownership transfers. The contract maintains a complete history of status changes and implements robust validation and security checks.

## Features

### Core Functionality
- **LEI Registration**: Register new LEIs with complete entity information
- **LEI Renewal**: Extend expiration dates of existing LEIs
- **Information Updates**: Modify entity information associated with LEIs
- **Status Management**: Change LEI status (ACTIVE, LAPSED, RETIRED, etc.)
- **Ownership Transfer**: Transfer LEI ownership between principals
- **Auto-Expiry**: Automatically update expired LEIs

### Security Features
- **Role-Based Access Control**: Contract owner and administrator system
- **Authorization Verification**: Ensures only authorized entities can perform sensitive operations
- **Data Validation**: LEI format validation and comprehensive error handling
- **Expiration Management**: Tracks and enforces LEI expiration

### Data Storage
- **LEI Registry**: Stores all LEI data and metadata
- **Principal-to-LEI Mapping**: Tracks LEIs owned by each principal
- **Status History**: Records all status changes for audit trail

## Contract Functions

### Administrative Functions
- `set-contract-owner`: Change the contract owner (owner only)
- `add-administrator`: Add a new administrator (owner only)
- `remove-administrator`: Remove an administrator (owner only)
- `is-admin`: Check if a principal is an administrator (read-only)

### LEI Management Functions
- `register-lei`: Register a new LEI (admin only)
- `renew-lei`: Renew an existing LEI (admin or owner)
- `update-lei-info`: Update LEI entity information (admin or owner)
- `change-lei-status`: Change LEI status (admin only)
- `transfer-lei`: Transfer LEI ownership (admin or current owner)
- `auto-expire-leis`: Batch update expired LEIs (admin only)

### Query Functions
- `get-lei-info`: Get complete information for an LEI
- `is-lei-active`: Check if an LEI is active and not expired
- `get-leis-by-principal`: Get all LEIs owned by a principal
- `get-lei-status-history`: Get the status change history of an LEI
- `verify-lei`: Comprehensive verification of LEI validity, status, and expiration

## LEI Statuses

The contract supports the following LEI statuses:
- `ACTIVE`: The LEI is valid and in use
- `LAPSED`: The LEI has lapsed but can be renewed
- `RETIRED`: The LEI has been permanently retired
- `MERGED`: The entity has merged with another entity
- `DUPLICATE`: The LEI is a duplicate of another LEI
- `EXPIRED`: The LEI has passed its expiration date

## Error Codes

The contract uses the following error codes:
- `ERR-NOT-AUTHORIZED (u100)`: Caller is not authorized for this operation
- `ERR-ALREADY-REGISTERED (u101)`: LEI is already registered
- `ERR-INVALID-LEI (u102)`: LEI format is invalid
- `ERR-NOT-FOUND (u103)`: LEI not found in registry
- `ERR-EXPIRED (u104)`: LEI is expired
- `ERR-INVALID-DATE (u105)`: Invalid date provided
- `ERR-INVALID-STATUS (u106)`: Invalid status value
- `ERR-INVALID-ADDRESS (u107)`: Invalid principal address

For verification functions:
- `u201`: LEI is not active
- `u202`: LEI is expired

## Usage Examples

### Register a new LEI
```clarity
(contract-call? .lei-registry register-lei 
  "GB54MN37H5S76R4Z0A16" 
  "Example Corporation Ltd" 
  u12345678 
  "GB" 
  "Limited Company" 
  "Companies House UK")
```

### Renew an existing LEI
```clarity
(contract-call? .lei-registry renew-lei 
  "GB54MN37H5S76R4Z0A16" 
  u23456789)
```

### Update LEI information
```clarity
(contract-call? .lei-registry update-lei-info 
  "GB54MN37H5S76R4Z0A16" 
  "Example Corporation Global Ltd" 
  "GB" 
  "Public Limited Company" 
  "Companies House UK")
```

### Change LEI status
```clarity
(contract-call? .lei-registry change-lei-status 
  "GB54MN37H5S76R4Z0A16" 
  "RETIRED")
```

### Transfer LEI ownership
```clarity
(contract-call? .lei-registry transfer-lei 
  "GB54MN37H5S76R4Z0A16" 
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

### Verify LEI validity
```clarity
(contract-call? .lei-registry verify-lei "GB54MN37H5S76R4Z0A16")
```

## Deployment

To deploy this contract on the Stacks blockchain:

1. Use Clarinet or the Stacks CLI to deploy the contract.
2. The deploying address will automatically become the contract owner and first administrator.
3. The contract owner can add additional administrators as needed.

## Integration

This contract can be integrated with:

- Financial compliance systems
- KYC/AML verification platforms
- Inter-bank transaction networks
- Financial reporting systems
- Decentralized finance (DeFi) applications requiring legal entity verification

## Security Considerations

- The contract owner has full administrative rights and can add/remove administrators
- Only administrators can register new LEIs and change LEI statuses
- LEI owners can renew, update, and transfer their LEIs
- All sensitive operations include authorization checks
- Status history provides a complete audit trail for compliance purposes