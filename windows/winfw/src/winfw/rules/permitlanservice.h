#pragma once

#include "ifirewallrule.h"

namespace rules
{

class PermitLanService : public IFirewallRule
{
public:

	PermitLanService() = default;
	~PermitLanService() = default;
	
	bool apply(IObjectInstaller &objectInstaller) override;

private:

	bool applyIpv4(IObjectInstaller &objectInstaller) const;
	bool applyIpv6(IObjectInstaller &objectInstaller) const;
};

}
