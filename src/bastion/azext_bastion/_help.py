# --------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.
#
# Code generated by aaz-dev-tools
# --------------------------------------------------------------------------------------------

# pylint: disable=line-too-long
# pylint: disable=too-many-lines

from knack.help_files import helps  # pylint: disable=unused-import


helps['network bastion ssh'] = """
type: command
short-summary: SSH to a virtual machine using Tunneling from Azure Bastion.
examples:
  - name: SSH to virtual machine using Azure Bastion using password.
    text: |
        az network bastion ssh --name MyBastionHost --resource-group MyResourceGroup --target-resource-id vmResourceId --auth-type password --username xyz
  - name: SSH to virtual machine using Azure Bastion using ssh key file.
    text: |
        az network bastion ssh --name MyBastionHost --resource-group MyResourceGroup --target-resource-id vmResourceId --auth-type ssh-key --username xyz --ssh-key C:/filepath/sshkey.pem
  - name: SSH to virtual machine using Azure Bastion using AAD.
    text: |
        az network bastion ssh --name MyBastionHost --resource-group MyResourceGroup --target-resource-id vmResourceId --auth-type AAD
"""

helps['network bastion rdp'] = """
type: command
short-summary: RDP to target Virtual Machine using Tunneling from Azure Bastion.
examples:
  - name: RDP to virtual machine using Azure Bastion.
    text: |
        az network bastion rdp --name MyBastionHost --resource-group MyResourceGroup --target-resource-id vmResourceId
"""

helps['network bastion tunnel'] = """
type: command
short-summary: Open a tunnel through Azure Bastion to a target virtual machine.
examples:
  - name: Open a tunnel through Azure Bastion to a target virtual machine.
    text: |
        az network bastion tunnel --name MyBastionHost --resource-group MyResourceGroup --target-resource-id vmResourceId --resource-port 22 --port 50022
"""