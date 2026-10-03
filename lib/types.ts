export type Role = "teacher" | "student" | "admin";
export type Account = { id: string; loginId: string; name: string; role: Role; mustChangePassword: boolean; classId?: string; studentNo?: number; needsClass?: boolean; requestedClassName?: string | null };
export type StatKey = "hp" | "attack" | "specialAttack" | "defense" | "specialDefense" | "speed";
export type Stats = Record<StatKey, number>;
export type Pet = { id: string; speciesId: string; level: number; xp: number; stage: number; skills: string[]; createdAt: string; representative: boolean; statAllocation?: Stats };
export type Grant = { id: string; sku: string; quantity: number; remaining: number; reference: string; note: string; createdAt: string; revoked: boolean };
export type LogEntry = { id: string; studentId: string | null; actorName: string; message: string; createdAt: string };
export type Student = Account & { pets: Pet[]; inventory: Grant[] };
export type FarmState = {
  needsSetup: boolean;
  user: Account | null;
  className: string;
  students: Student[];
  pets: Pet[];
  inventory: Grant[];
  logs: LogEntry[];
};

// POST /api/farm uses the existing classroom identity through an HttpOnly session.
// login: {classId,code}; teacherLogin: {email,password}; signup: {email,password,displayName,className}; logout: {}; purchase: {sku,quantity,expectedPrice,requestId};
// choosePet: {speciesId,requestId}; useItem: {petId,sku,quantity,requestId};
// representative: {petId,requestId}; teacher actions: grant, adjustLevel, points, price, refund.
// allocateStats: {petId,allocation:{hp,attack,specialAttack,defense,specialDefense,speed},requestId}.
