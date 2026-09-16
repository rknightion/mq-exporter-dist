# Test fixture only: grant one account one right without importing a whole policy.
# Native API: https://learn.microsoft.com/windows/win32/secmgmt/managing-account-permissions
function Grant-TestServiceLogon([Security.Principal.SecurityIdentifier]$Sid) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class TestServiceRight {
    [StructLayout(LayoutKind.Sequential)]
    struct Attributes {
        public uint Length;
        public IntPtr RootDirectory, ObjectName;
        public uint Flags;
        public IntPtr SecurityDescriptor, SecurityQualityOfService;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct UnicodeString { public ushort Length, MaximumLength; public IntPtr Buffer; }
    [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr system, ref Attributes attributes, uint access, out IntPtr handle);
    [DllImport("advapi32.dll")] static extern uint LsaAddAccountRights(IntPtr handle, byte[] sid, UnicodeString[] rights, uint count);
    [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr handle);
    [DllImport("advapi32.dll")] static extern uint LsaNtStatusToWinError(uint status);
    static void Check(uint status) { if (status != 0) throw new Win32Exception((int)LsaNtStatusToWinError(status)); }
    public static void Grant(byte[] sid) {
        var attributes = new Attributes();
        attributes.Length = (uint)Marshal.SizeOf(typeof(Attributes));
        IntPtr handle;
        Check(LsaOpenPolicy(IntPtr.Zero, ref attributes, 0x810, out handle));
        var right = new UnicodeString();
        try {
            const string name = "SeServiceLogonRight";
            right.Buffer = Marshal.StringToHGlobalUni(name);
            right.Length = (ushort)(name.Length * 2);
            right.MaximumLength = (ushort)(right.Length + 2);
            Check(LsaAddAccountRights(handle, sid, new[] { right }, 1));
        } finally {
            if (right.Buffer != IntPtr.Zero) Marshal.FreeHGlobal(right.Buffer);
            LsaClose(handle);
        }
    }
}
'@
    $bytes = New-Object byte[] $Sid.BinaryLength
    $Sid.GetBinaryForm($bytes,0)
    [TestServiceRight]::Grant($bytes)
}
