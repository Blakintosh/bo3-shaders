#ifndef BLAK_QUATERNION_INCLUDED
#define BLAK_QUATERNION_INCLUDED

float4 Quaternion_FromRotationMatrix(const float3x3 m)
{
    // TODO: Modify so we don't need to do transpose every frame
    float4 q;
    float r22 = m[2][2];
    if (r22 <= 0.f)  // x^2 + y^2 >= z^2 + w^2
    {
        float dif10 = m[1][1] - m[0][0];
        float omr22 = 1.f - r22;
        if (dif10 <= 0.f)  // x^2 >= y^2
        {
            float fourXSqr = omr22 - dif10;
            float inv4x = 0.5f / sqrt(fourXSqr);
            q.x = fourXSqr * inv4x;
            q.y = (m[0][1] + m[1][0]) * inv4x;
            q.z = (m[0][2] + m[2][0]) * inv4x;
            q.w = (m[1][2] - m[2][1]) * inv4x;
        }
        else  // y^2 >= x^2
        {
            float fourYSqr = omr22 + dif10;
            float inv4y = 0.5f / sqrt(fourYSqr);
            q.x = (m[0][1] + m[1][0]) * inv4y;
            q.y = fourYSqr * inv4y;
            q.z = (m[1][2] + m[2][1]) * inv4y;
            q.w = (m[2][0] - m[0][2]) * inv4y;
        }
    }
    else  // z^2 + w^2 >= x^2 + y^2
    {
        float sum10 = m[1][1] + m[0][0];
        float opr22 = 1.f + r22;
        if (sum10 <= 0.f)  // z^2 >= w^2
        {
            float fourZSqr = opr22 - sum10;
            float inv4z = 0.5f / sqrt(fourZSqr);
            q.x = (m[0][2] + m[2][0]) * inv4z;
            q.y = (m[1][2] + m[2][1]) * inv4z;
            q.z = fourZSqr * inv4z;
            q.w = (m[0][1] - m[1][0]) * inv4z;
        }
        else  // w^2 >= z^2
        {
            float fourWSqr = opr22 + sum10;
            float inv4w = 0.5f / sqrt(fourWSqr);
            q.x = (m[1][2] - m[2][1]) * inv4w;
            q.y = (m[2][0] - m[0][2]) * inv4w;
            q.z = (m[0][1] - m[1][0]) * inv4w;
            q.w = fourWSqr * inv4w;
        }
    }

    return q;
}

float4 Quaternion_Conjugate(const float4 quat) 
{
    return quat * float4(-1, -1, -1, 1);
}


float4 Quaternion_Multiply(const float4 q1, const float4 q2) 
{
    return float4(q2.xyz * q1.w + q1.xyz * q2.w + cross(q1.xyz, q2.xyz),
                  q1.w * q2.w - dot(q1.xyz, q2.xyz));
}

float3 Quaternion_TransformVector(const float4 quat, const float3 vec) 
{
    float3 t = 2 * cross(quat.xyz, vec);
    return vec + quat.w * t + cross(quat.xyz, t);
}

#endif // BLAK_QUATERNION_INCLUDED