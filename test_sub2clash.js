// 测试基于 sub2clash 的 AnyTLS 实现
function parseAnyTLSLink(link) {
    try {
        const url = new URL(link);

        const server = url.hostname;
        const port = parseInt(url.port) || 443;

        // 密码可以在 username 或 password 位置
        const username = url.username ? decodeURIComponent(url.username) : '';
        const password = url.password ? decodeURIComponent(url.password) : username;

        const params = new URLSearchParams(url.search);
        const insecure = params.get('insecure') === '1';
        const sni = params.get('sni') || '';

        const remark = url.hash ? decodeURIComponent(url.hash.substring(1)) : `${server}:${port}`;

        return {
            server,
            port,
            password,
            sni,
            skipCertVerify: insecure,
            remark
        };
    } catch (e) {
        console.error('解析失败:', e);
        return null;
    }
}

function anyTLSToClashYAML(node) {
    const config = {
        name: node.remark,
        type: 'anytls',
        server: node.server,
        port: node.port,
        password: node.password
    };

    if (node.sni) {
        config.sni = node.sni;
    }
    if (node.skipCertVerify) {
        config['skip-cert-verify'] = true;
    }
    config.udp = true;

    const pairs = [];
    for (const [key, value] of Object.entries(config)) {
        if (typeof value === 'string') {
            pairs.push(`${key}: ${value}`);
        } else if (typeof value === 'boolean') {
            pairs.push(`${key}: ${value}`);
        } else if (typeof value === 'number') {
            pairs.push(`${key}: ${value}`);
        }
    }

    return `  - { ${pairs.join(', ')} }`;
}

console.log("========== sub2clash 标准实现测试 ==========\n");

// 测试1: VPS-play 生成的链接
const link1 = "anytls://5bBE8BCq4onbM95B@168.231.97.89:52792?insecure=1&allowInsecure=1&sni=168.231.97.89&fp=chrome#AnyTLS-168.231.97.89";
console.log("测试1: VPS-play格式");
console.log("输入:", link1);
const node1 = parseAnyTLSLink(link1);
console.log("解析:", JSON.stringify(node1, null, 2));
if (node1) {
    console.log("YAML:", anyTLSToClashYAML(node1));
}

console.log("\n测试2: 机场格式（有SNI）");
const link2 = "anytls://7058fcdd-992a-4761-a8de-8e1b7619962d@152.53.54.139:36001?insecure=1&sni=hk.zongyunti.site#剩余流量：99983.38 GB";
const node2 = parseAnyTLSLink(link2);
console.log("解析:", JSON.stringify(node2, null, 2));
if (node2) {
    console.log("YAML:", anyTLSToClashYAML(node2));
}

console.log("\n测试3: 无SNI");
const link3 = "anytls://test123@1.2.3.4:443?insecure=1#TestNode";
const node3 = parseAnyTLSLink(link3);
console.log("解析:", JSON.stringify(node3, null, 2));
if (node3) {
    console.log("YAML:", anyTLSToClashYAML(node3));
}

console.log("\n========== 测试完成 ==========");
