#include "pipelines/common.hlsli"

cbuffer Data : register(b4) {
	float2 u_size;
	float u_max_steps;
	float u_stride;
	uint u_depth;
	uint u_sss_buffer;
};

// based on http://casual-effects.blogspot.com/2014/08/screen-space-ray-tracing.html
void raycast(float3 csOrig, float3 csDir, float stride, float jitter, uint2 ip0) {
	float3 csEndPoint = csOrig + abs(csOrig.z * 0.1) * csDir;

	float4 H0 = transformPosition(csOrig, Global_vs_to_ndc);
	float4 H1 = transformPosition(csEndPoint, Global_vs_to_ndc);

	float k0 = 1 / H0.w, k1 = 1 / H1.w;

	float2 P0 = toScreenUV(H0.xy * k0 * 0.5 + 0.5) * u_size;
	float2 P1 = toScreenUV(H1.xy * k1 * 0.5 + 0.5) * u_size;

	float2 delta = P1 - P0;
	bool permute = abs(delta.x) < abs(delta.y);
	if (permute) {
		P0 = P0.yx;
		P1 = P1.yx;
		delta = delta.yx;
	}

	float stepDir = sign(delta.x);
	float invdx = stepDir / delta.x;

	float dk = ((k1 - k0) * invdx) * stride;
	float2  dP = (float2(stepDir, delta.y * invdx)) * stride;

	float2 P = P0;
	float k = k0;

	uint max_steps = uint(min(abs(P1.x - P0.x), u_max_steps)) >> 2;
	for (uint j = 0; j < 4; ++j) {
		P += dP * jitter;
		k += dk * jitter;
		for (uint i = 0; i < max_steps; ++i) {
			float rayZFar = 1 / k;

			float2 p = permute ? P.yx : P;
			if (any(p < 0)) break;
			if (any(p > u_size)) break;

			float depth = sampleBindlessLod(LinearSamplerClamp, u_depth, p / u_size, 0).x;
			depth = toLinearDepth(depth);
			
			float dif = rayZFar - depth;
			if (dif < depth * 0.02 && dif > 1e-3) {
				bindless_rw_textures[u_sss_buffer][ip0] = 0;
				return;
			}

			P += dP;
			k += dk;
		}
			P -= dP;
			k -= dk;
		dP *= 2;
		dk *= 2;
	}
	bindless_rw_textures[u_sss_buffer][ip0] = 1;
}

[numthreads(16, 16, 1)]
void main(uint3 thread_id : SV_DispatchThreadID) {
	float2 inv_size = 1 / u_size;
	float2 uv = float2(thread_id.xy) * inv_size;
	float3 p = getPositionWS(u_depth, uv);
	float4 o = mul(float4(p, 1), Global_ws_to_vs);
	float3 d = mul(Global_light_dir.xyz, (float3x3)Global_ws_to_vs);
	float rr = hash(float2(thread_id.xy) + 0.1 * Global_time);
	raycast(o.xyz, d.xyz, u_stride, rr, thread_id.xy);
}