# Aurora Dell 5421

Aurora Stable with a declarative initramfs tailored to the Dell Latitude 5421
(Intel graphics, NVMe, encrypted Btrfs and TPM2). This image is hardware-specific.

Includes Btrfs Assistant, Snapper, NordVPN/GUI and ChatGPT. Removes Sunshine;
otherwise preserves Aurora. No personal data, disk UUIDs or TPM secrets are included.

The initramfs is built and checked in GitHub Actions, not regenerated on the PC.
Builds follow Aurora Stable and retain its version. Published as
`ghcr.io/0t4k0n/aurora-dell5421:stable`.

Publication requires repository secrets `SIGNING_SECRET` and `COSIGN_PASSWORD`,
and the matching public key in `cosign.pub`. Keep private keys outside this repository.
