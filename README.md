# Deployment Errors & Fixes

This section documents the issues encountered while deploying the Bicep template and how they were resolved.

---

## 1. Bicep Error – BCP144

**Error:**

```
BCP144: Directly referencing a resource or module collection is not currently supported here.
Apply an array indexer to the expression.
```

**Cause:**  
Resource collections created using `for` loops (e.g., `resource vms = [for ...]`) cannot be directly iterated using:

```bicep
[for vm in vms: vm.name]   // ❌ Not allowed
```

Bicep requires indexed access when working with resource collections.

**Fix:**  
Replace direct collection iteration with indexed access:

```bicep
output vmNames array = [
  for i in range(0, vmCount): vms[i].name
]
```

Same rule applies to:

- `publicIps`
    
- `nics`
    
- Any resource defined using a loop
    

---

## 2. Azure Deployment Error – SKU Not Available

**Error:**

```
SkuNotAvailable: Standard_B2s is not available in location 'eastus'
```

**Cause:**  
The selected VM size was temporarily unavailable in the chosen region due to capacity constraints.

**Fix Options:**

- Change VM size (e.g., use newer v2 or v5 SKUs)
    
- Change deployment region
    
- Check available SKUs:
    

```bash
az vm list-skus --location eastus --output table
```

---

## 3. Azure Deployment Error – QuotaExceeded

**Error:**

```
QuotaExceeded: Operation could not be completed as it results in exceeding approved standardBpsv2Family Cores quota
```

**Cause:**  
The subscription had insufficient vCPU quota for the selected VM family in the region.

Azure enforces:

- Regional vCPU limits
    
- Per-VM-family quotas
    

Even if a SKU is available, deployment fails if quota is 0.

**How to Check Quota:**

```bash
az vm list-usage --location eastus --output table
```

**Fix Options:**

- Choose a VM size from a family with available quota
    
- Deploy to another region (e.g., westeurope)
    
- Request a quota increase via Azure Portal → Subscriptions → Usage + quotas
    
---

## 4. PolicyDefinitionNotFound

### Error

PolicyDefinitionNotFound

### Cause

Incorrect reference to built-in Azure Policy definitions.

Attempted usage:

policyDefinitionId: subscriptionResourceId(...)

Built-in policies are not subscription-scoped. They are tenant-scoped.

### Resolution

Use the global provider path:

policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/<GUID>'

If still failing:

- Verify policy exists:
    

az policy definition list --output table

- Ensure providers are registered:
    

az provider register --namespace Microsoft.Authorization  
az provider register --namespace Microsoft.PolicyInsights

---

## 5. Lessons Learned

- Resource collections in Bicep require indexed access.
    
- SKU availability varies by region and capacity.
    
- Subscription quotas can block deployments even when SKUs exist.
    
- Always validate before deployment:
    
- Built-in Azure Policies are tenant-scoped, not subscription-scoped.
    
- Partial deployments can leave resources in transient states.

```bash
az deployment group validate \
  --resource-group <rg-name> \
  --template-file pre.bicep \
  --parameters @parameters.json
```

---

## 6. Recommended Best Practice Improvements

- Parameterize `vmSize` instead of hardcoding it.
    
- Avoid region hardcoding; pass `location` as a parameter.
    
- Check quota before large deployments.
    
- Use newer VM generations (v2/v5) for better availability.
    
------------

az deployment group create \
  --resource-group myResourceGroup \
  --template-file main.bicep \
  --parameters @parameters.dev.json
