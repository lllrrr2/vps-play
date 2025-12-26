// 测试单行 Flow 格式
function anyTLSToClashYAML(node) {
    // 使用单行 Flow 格式（花括号），与 Clash Meta 标准一致
    // 参考: { name: 节点名, type: anytls, server: 1.2.3.4, port: 443, ... }

    // 构建配置项数组
    const parts = [
        `name: ${node.remark}`,
        `type: anytls`,
        `server: ${node.server}`,
        `port: ${node.port}`,
        `password: ${node.password}`,
        `'client-fingerprint': ${node.fingerprint}`,
        `udp: true`,
        `alpn: [h2, http/1.1]`,
        `sni: ${node.sni}`,
        `'skip-cert-verify': ${node.skipCertVerify}`
    ];

    // 如果是 Any-Reality，添加 reality-opts
    if (node.security === 'reality' && node.publicKey) {
        let realityParts = [`'public-key': ${node.publicKey}`];
        if (node.shortId) {
            realityParts.push(`'short-id': ${node.shortId}`);
        }
        parts.push(`'reality-opts': { ${realityParts.join(', ')} }`);
    }

    return `    - { ${parts.join(', ')} }`;
}

// 测试
const testNodes = [
    {
        password: "7058fcdd-992a-4761-a8de-8e1b7619962d",
        server: "152.53.54.139",
        port: 36001,
        remark: "美国03",
        skipCertVerify: true,
        sni: "hk.zongyunti.site",
        fingerprint: "chrome",
        security: "",
        publicKey: "",
        shortId: ""
    },
    {
        password: "test-pass",
        server: "1.2.3.4",
        port: 443,
        remark: "Any-Reality节点",
        skipCertVerify: true,
        sni: "apple.com",
        fingerprint: "chrome",
        security: "reality",
        publicKey: "ABCDEFG123",
        shortId: "abc123"
    }
];

console.log("========== 单行 Flow 格式测试 ==========\n");
console.log("proxies:");
testNodes.forEach(node => {
    console.log(anyTLSToClashYAML(node));
});
console.log("\n========== 测试完成 ==========");
