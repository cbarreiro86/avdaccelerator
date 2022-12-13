targetScope = 'subscription'

// ========== //
// Parameters //
// ========== //
@description('Required. Location where to deploy AVD session hosts.')
param avdSessionHostLocation string

@description('Required. Location where to deploy AVD management plane.')
param avdManagementPlaneLocation string

@description('Optional. AVD workload subscription ID, multiple subscriptions scenario.')
param avdWorkloadSubsId string

@description('AVD Resource Group Name for the service objects.')
param avdServiceObjectsRgName string

@description('Resource Group name for the session hosts.')
param avdComputeObjectsRgName string

@description('Resource Group Name for Azure Files.')
param avdStorageObjectsRgName string

@description('Azure Virtual Desktop enterprise application object ID.')
param avdEnterpriseAppObjectId string

@description('Create custom Start VM on connect role.')
param createStartVmOnConnectCustomRole bool

@description('Deploy new session hosts.')
param avdDeploySessionHosts bool

@description('Required, The service providing domain services for Azure Virtual Desktop.')
param avdIdentityServiceProvider string

@description('Required, Identity ID to grant RBAC role to access AVD application group.')
param avdApplicationGroupIdentitiesIds array

@description('Deploy scaling plan.')
param avdDeployScalingPlan bool

@description('Managed Identity name.')
param avdManagedIdentityName string

@description('GUID for built role Reader.')
param readerRoleId string

@description('GUID for built in role ID of Storage Account Contributor.')
param storageAccountContributorRoleId string

@description('GUID for built in role ID of Desktop Virtualization Power On Off Contributor.')
param avdVmPowerStateContributor string

@description('Optional. Deploy Storage setup.')
param createStorageDeployment bool

@description('Required. Tags to be applied to resources')
param avdTags object

@description('Do not modify, used to set unique value for resource deployment.')
param time string = utcNow()

// =========== //
// Deployments //
// =========== //

// Managed identity for fslogix/msix app attach
module ManagedIdentity '../../../carml/1.2.0/Microsoft.ManagedIdentity/userAssignedIdentities/deploy.bicep' = if (createStorageDeployment && (avdIdentityServiceProvider != 'AAD')) {
  scope: resourceGroup('${avdWorkloadSubsId}', '${avdStorageObjectsRgName}')
  name: 'Managed-Identity-${time}'
  params: {
    name: avdManagedIdentityName
    location: avdSessionHostLocation
    tags: avdTags
  }
}

// Introduce delay for management VM to be ready.
module ManagedIdentityDelay '../../../carml/1.0.0/Microsoft.Resources/deploymentScripts/deploy.bicep' = if (createStorageDeployment && (avdIdentityServiceProvider != 'AAD')) {
  scope: resourceGroup('${avdWorkloadSubsId}', '${avdStorageObjectsRgName}')
  name: 'AVD-Storage-Identity-Delay-${time}'
  params: {
      name: 'AVD-storageManagedIdentityDelay-${time}'
      location: avdSessionHostLocation
      azPowerShellVersion: '6.2'
      cleanupPreference: 'Always'
      timeout: 'PT10M'
      scriptContent: '''
      Write-Host "Start"
      Get-Date
      Start-Sleep -Seconds 60
      Write-Host "Stop"
      Get-Date
      '''
  }
  dependsOn: [
    ManagedIdentity
  ]
}

// RBAC Roles.
// Start VM on connect.
module startVMonConnectRole '../../../carml/1.2.0/Microsoft.Authorization/roleDefinitions/subscription/deploy.bicep' = if (createStartVmOnConnectCustomRole) {
  scope: subscription(avdWorkloadSubsId)
  name: 'Start-VM-on-Connect-Role-${time}'
  params: {
    subscriptionId: avdWorkloadSubsId
    description: 'Start VM on connect AVD'
    roleName: 'StartVMonConnect-AVD'
    location: avdSessionHostLocation
    actions: [
      'Microsoft.Compute/virtualMachines/start/action'
      'Microsoft.Compute/virtualMachines/*/read'
    ]
    assignableScopes: [
      '/subscriptions/${avdWorkloadSubsId}'
    ]
  }
}

// RBAC role Assignments.
// Start VM on connect.
module startVMonConnectRoleAssign '../../../carml/1.2.0/Microsoft.Authorization/roleAssignments/resourceGroup/deploy.bicep' = if (createStartVmOnConnectCustomRole) {
  name: 'Start-VM-OnConnect-RoleAssign-${time}'
  scope: resourceGroup('${avdWorkloadSubsId}', '${avdComputeObjectsRgName}')
  params: {
    roleDefinitionIdOrName: createStartVmOnConnectCustomRole ? startVMonConnectRole.outputs.resourceId : '/subscriptions/${avdWorkloadSubsId}/providers/Microsoft.Authorization/roleDefinitions/${avdVmPowerStateContributor}'
    principalId: avdEnterpriseAppObjectId
  }
  dependsOn: [
    startVMonConnectRole
  ]
}

// FSLogix.
module RoleAssign '../../../carml/1.2.0/Microsoft.Authorization/roleAssignments/resourceGroup/deploy.bicep' = if (createStorageDeployment && (avdIdentityServiceProvider != 'AAD')) {
  name: 'storage-UserAIdentity-RoleAssign-${time}'
  scope: resourceGroup('${avdWorkloadSubsId}', '${avdStorageObjectsRgName}')
  params: {
    roleDefinitionIdOrName: '/subscriptions/${avdWorkloadSubsId}/providers/Microsoft.Authorization/roleDefinitions/${storageAccountContributorRoleId}'
    principalId: createStorageDeployment ? ManagedIdentity.outputs.principalId: ''
  }
  dependsOn: [
    ManagedIdentityDelay
  ]
}
//FSLogix reader.
module ReaderRoleAssign '../../../carml/1.2.0/Microsoft.Authorization/roleAssignments/resourceGroup/deploy.bicep' = if (createStorageDeployment && (avdIdentityServiceProvider != 'AAD')) {
  name: 'storage-UserAIdentity-ReaderRoleAssign-${time}'
  scope: resourceGroup('${avdWorkloadSubsId}', '${avdStorageObjectsRgName}')
  params: {
    roleDefinitionIdOrName: '/subscriptions/${avdWorkloadSubsId}/providers/Microsoft.Authorization/roleDefinitions/${readerRoleId}'
    principalId: createStorageDeployment ? ManagedIdentity.outputs.principalId: ''
  }
  dependsOn: [
    ManagedIdentityDelay
  ]
}

//Scaling plan compute RG.
module scalingPlanRoleAssignCompute '../../../carml/1.2.0/Microsoft.Authorization/roleAssignments/resourceGroup/deploy.bicep' = if (avdDeployScalingPlan) {
  name: 'Scaling-Plan-Assign-Compute-${time}'
  scope: resourceGroup('${avdWorkloadSubsId}', '${avdComputeObjectsRgName}')
  params: {
    roleDefinitionIdOrName: '/subscriptions/${avdWorkloadSubsId}/providers/Microsoft.Authorization/roleDefinitions/${avdVmPowerStateContributor}' 
    principalId: avdEnterpriseAppObjectId
  }
  dependsOn: []
}

//Scaling plan service objects RG.
module scalingPlanRoleAssignServiceObjects '../../../carml/1.2.0/Microsoft.Authorization/roleAssignments/resourceGroup/deploy.bicep' = if (avdDeployScalingPlan) {
  name: 'Scaling-Plan-Assign-Service-${time}'
  scope: resourceGroup('${avdWorkloadSubsId}', '${avdServiceObjectsRgName}')
  params: {
    roleDefinitionIdOrName: '/subscriptions/${avdWorkloadSubsId}/providers/Microsoft.Authorization/roleDefinitions/${avdVmPowerStateContributor}' 
    principalId: avdEnterpriseAppObjectId
  }
  dependsOn: []
}

module avdAadIdentityLoginAccess '../../../carml/1.2.0/Microsoft.Authorization/roleAssignments/resourceGroup/deploy.bicep' =  [for avdApplicationGropupIdentityId in avdApplicationGroupIdentitiesIds: if (avdIdentityServiceProvider == 'AAD' && !empty(avdApplicationGroupIdentitiesIds)) {
  name: 'AAD-VM-Role-Assign-${take('${avdApplicationGropupIdentityId}', 6)}-${time}'
  scope: resourceGroup('${avdWorkloadSubsId}', '${avdComputeObjectsRgName}')
  params: {
    roleDefinitionIdOrName: 'Virtual Machine User Login' 
    principalId: avdApplicationGropupIdentityId
  }
  dependsOn: []
}]
//

// =========== //
// Outputs //
// =========== //
output ManagedIdentityResourceId string = (createStorageDeployment && (avdIdentityServiceProvider != 'AAD')) ? ManagedIdentity.outputs.resourceId: ''
output ManagedIdentityClientId string = (createStorageDeployment && (avdIdentityServiceProvider != 'AAD')) ? ManagedIdentity.outputs.clientId: ''
